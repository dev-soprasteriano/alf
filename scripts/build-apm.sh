#!/usr/bin/env bash
# Builds one self-contained APM skill bundle per skill into dist/skills/, and dist/user-apm.yml,
# the manifest a single user copies to ~/.apm/apm.yml. Run by `task build-apm`.
# `--check` builds into a temp folder and fails if dist/ differs from it. CI runs it.
# Both modes fail when README.md differs from src/. See check_readme. A build writes dist/ first
# and then exits with status 3, which scripts/update-upstream.sh reads as "built, README.md differs".
# Never edit dist/ by hand. See AGENTS.md.
#
# Written for bash 3.2 (macOS /bin/bash): plain variables, loops and case only.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM_DIR="$REPO_DIR/src/upstream"
SKILLS_DIR="$REPO_DIR/src/skills"
DEPS_FILE="$REPO_DIR/src/skill-dependencies.txt"
DIST_DIR="$REPO_DIR/dist"
README="$REPO_DIR/README.md"
ALF_REPO="dev-soprasteriano/alf"
OVERLAY_START='<!-- overlay:start -->'
OVERLAY_END='<!-- overlay:end -->'

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

usage() {
  printf 'Usage: scripts/build-apm.sh [--check]\n' >&2
  exit 2
}

# Frontmatter of a SKILL.md, from line 1 through the closing ---.
frontmatter() {  # SKILL.md
  awk '{ print } NR > 1 && /^---$/ { exit }' "$1"
}

# Everything after the closing --- of a SKILL.md.
body() {  # SKILL.md
  awk 'seen { print } !seen && NR > 1 && /^---$/ { seen = 1 }' "$1"
}

# The overlay block of a wrapper, markers included.
overlay() {  # SKILL.md
  awk -v s="$OVERLAY_START" -v e="$OVERLAY_END" '$0 == s { on = 1 } on { print } $0 == e { exit }' "$1"
}

# The upstream skill a wrapper points at, as slug/skill. Prints nothing for an in-house skill.
upstream_ref() {  # SKILL.md
  grep -o '`\.\./\.\./upstream/[^`]*/SKILL\.md`' "$1" | head -n 1 \
    | sed 's#^`\.\./\.\./upstream/##; s#/SKILL\.md`$##' || true
}

# Names of the skills in src/skills/, sorted.
list_skills() {
  local d
  for d in "$SKILLS_DIR"/*/; do
    if [[ -f "$d/SKILL.md" ]]; then
      basename "$d"
    fi
  done
}

# The names listed under a key in src/skill-dependencies.txt, space-separated.
# Key is a skill (its dependencies) or "<skill> mentions" (its mentions).
names_for() {  # key
  [[ -f "$DEPS_FILE" ]] || return 0
  awk -v n="$1" '
    /^#/ || !/:/ { next }
    { key = $0; sub(/:.*/, "", key); gsub(/^ +| +$/, "", key) }
    key == n { val = $0; sub(/^[^:]*:/, "", val); gsub(/^ +| +$/, "", val); print val; exit }
  ' "$DEPS_FILE"
}

# Dependencies a skill declares, space-separated.
deps_for() {  # skill
  names_for "$1"
}

# Names a skill mentions without calling, space-separated.
mentions_for() {  # skill
  names_for "$1 mentions"
}

# Regex that matches a skill name used as a call: /name, `name`, "name", 'name', or "name skill".
name_pattern() {  # name
  local n="$1" pat
  pat="(^|[ (])/${n}([^A-Za-z0-9/_-]|\$)"
  pat="$pat|\`${n}\`|\"${n}\"|'${n}'|(^|[^A-Za-z0-9/_.-])${n} skill"
  printf '%s\n' "$pat"
}

# Writes dist/skills/<skill>/ into the output folder: the whole upstream folder, the wrapper's
# frontmatter, the upstream body and the overlay. In-house skills are copied as they are.
build_skill() {  # skill out
  local skill="$1" out="$2" src dest ref slug up deps dep
  src="$SKILLS_DIR/$skill"
  dest="$out/skills/$skill"
  mkdir -p "$dest"
  ref="$(upstream_ref "$src/SKILL.md")"
  if [[ -z "$ref" ]]; then
    cp -R "$src/." "$dest/"
  else
    slug="${ref%%/*}"
    up="$UPSTREAM_DIR/$ref"
    [[ -f "$up/SKILL.md" ]] || die "$src/SKILL.md points at $ref, which does not exist"
    grep -q "$OVERLAY_END" "$src/SKILL.md" || die "$src/SKILL.md has no overlay markers"
    cp -R "$up/." "$dest/"
    cp "$UPSTREAM_DIR/$slug/LICENSE" "$dest/LICENSE"
    {
      frontmatter "$src/SKILL.md"
      printf '\n'
      body "$up/SKILL.md"
      printf '\n'
      overlay "$src/SKILL.md"
    } > "$dest/SKILL.md"
  fi
  deps="$(deps_for "$skill")"
  if [[ -n "$deps" ]]; then
    {
      printf 'name: %s\nversion: 1.0.0\ndependencies:\n  apm:\n' "$skill"
      for dep in $deps; do
        printf '    - %s/dist/skills/%s\n' "$ALF_REPO" "$dep"
      done
    } > "$dest/apm.yml"
  fi
}

# Writes dist/user-apm.yml, which lists every skill for a single user.
write_user_manifest() {  # out
  local out="$1" skill
  {
    printf 'name: alf\nversion: 1.0.0\ntargets:\n  - claude\n  - copilot\n'
    printf 'dependencies:\n  apm:\n'
    for skill in $(list_skills); do
      printf '    - %s/dist/skills/%s\n' "$ALF_REPO" "$skill"
    done
    printf '  mcp: []\n'
  } > "$out/user-apm.yml"
}

# Fails when a skill names another skill by name and does not declare it, or declares a name
# that is not a skill. Scans the built .md files of each skill.
check_references() {  # out
  local out="$1" skill ref refname target wrapper declared targets dep errs=0 pairs
  pairs="$WORK/pairs.tsv"
  : > "$pairs"
  for skill in $(list_skills); do
    printf '%s\t%s\n' "$skill" "$skill" >> "$pairs"
    ref="$(upstream_ref "$SKILLS_DIR/$skill/SKILL.md")"
    if [[ -n "$ref" ]]; then
      refname="${ref#*/}"
      if [[ "$refname" != "$skill" ]]; then
        printf '%s\t%s\n' "$refname" "$skill" >> "$pairs"
      fi
    fi
  done
  for wrapper in $(list_skills); do
    declared=" $(deps_for "$wrapper") "
    mentioned=" $(mentions_for "$wrapper") "
    for dep in $(deps_for "$wrapper") $(mentions_for "$wrapper"); do
      if [[ ! -d "$SKILLS_DIR/$dep" ]]; then
        printf 'error: %s declares %s, which is not a skill\n' "$wrapper" "$dep" >&2
        errs=1
      fi
    done
    targets=""
    while IFS=$'\t' read -r refname target; do
      if [[ "$target" == "$wrapper" ]]; then continue; fi
      case " $targets " in *" $target "*) continue ;; esac
      if grep -r --include='*.md' -E -q -e "$(name_pattern "$refname")" "$out/skills/$wrapper"; then
        targets="$targets $target"
      fi
    done < "$pairs"
    for target in $targets; do
      case "$declared$mentioned" in
        *" $target "*) ;;
        *)
          printf 'error: %s names %s, but %s does not list it. Add it as a dependency, or as a mention if it is not called: %s\n' \
            "$wrapper" "$target" "$DEPS_FILE" "$wrapper mentions: $target" >&2
          errs=1
          ;;
      esac
    done
  done
  if [[ "$errs" -ne 0 ]]; then
    die "fix $DEPS_FILE, then run task build-apm"
  fi
}

# ---- README.md check ----
# README.md must match src/ in three ways. AGENTS.md lists them under "Editing rules".
# Each check prints one "error: ..." line per difference.

readme_ok=1

readme_error() {  # message
  printf 'error: %s\n' "$*" >&2
  readme_ok=0
}

# Passes when the frontmatter of a skill sets disable-model-invocation to true.
user_only() {  # skill
  frontmatter "$SKILLS_DIR/$1/SKILL.md" \
    | grep -i -E '^disable-model-invocation:[[:space:]]*true([[:space:]]|$)' > /dev/null
}

# Skills the agent may start by itself.
agent_started_skills() {
  local skill
  for skill in $(list_skills); do
    user_only "$skill" || printf '%s\n' "$skill"
  done
}

# Skills that point at no upstream skill.
in_house_skills() {
  local skill
  for skill in $(list_skills); do
    [[ -n "$(upstream_ref "$SKILLS_DIR/$skill/SKILL.md")" ]] || printf '%s\n' "$skill"
  done
}

# The code in README.md: every fenced block, then every code span.
readme_code() {
  sed -n '/^ *```/,/^ *```/p' "$README"
  grep -o '`[^`]*`' "$README" || true
}

# Check 1. A block sits between one "<!-- readme:<block> start -->" line and one end line.
# Its code spans must name exactly the skills that the list command prints.
check_readme_block() {  # block list-command rule
  local block="$1" list="$2" rule="$3" marker count name
  local start="<!-- readme:$block start -->" end="<!-- readme:$block end -->"
  for marker in "$start" "$end"; do
    count="$(grep -c -x -F -- "$marker" "$README" || true)"
    if [[ "$count" -ne 1 ]]; then
      readme_error "README.md must have one \"$marker\" line, and has $count"
      return
    fi
  done
  "$list" | sort > "$WORK/want.txt"
  sed -n "/^$start\$/,/^$end\$/p" "$README" \
    | { grep -o '`[^`]*`' || true; } | tr -d '`' | sort -u > "$WORK/got.txt"
  # comm -23 prints the lines only in want.txt, comm -13 the lines only in got.txt.
  while IFS= read -r name; do
    readme_error "README.md block \"$block\" does not list $name. The block lists $rule."
  done < <(comm -23 "$WORK/want.txt" "$WORK/got.txt")
  while IFS= read -r name; do
    readme_error "README.md block \"$block\" lists $name. The block lists only $rule."
  done < <(comm -13 "$WORK/want.txt" "$WORK/got.txt")
}

# Check 2. Every /name in the code of README.md must be a skill. tr puts each word on its own
# line: it replaces every character that a path cannot hold with a newline. A path such as
# /tmp/x or ~/.apm/ stays one word, so only a word that is exactly /name counts.
check_readme_names() {
  local name
  while IFS= read -r name; do
    [[ -f "$SKILLS_DIR$name/SKILL.md" ]] || readme_error "README.md names $name, which is not a skill"
  done < <(readme_code | LC_ALL=C tr -c 'A-Za-z0-9_./~\n-' '\n' | grep -E '^/[a-z][a-z0-9-]*$' | sort -u)
}

# Check 3. README.md must hold the URL of every upstream, from the "Upstream:" line of its
# PIN.md. The URL must end there: https://host/a/b does not match https://host/a/b-more.
check_readme_upstreams() {
  local pin url
  for pin in "$UPSTREAM_DIR"/*/PIN.md; do
    [[ -f "$pin" ]] || continue
    url="$(sed -n 's/^Upstream: *//p' "$pin" | head -n 1 | tr -d '\r')"
    url="${url%/}"
    if [[ -z "$url" ]]; then
      readme_error "$pin has no \"Upstream: <url>\" line"
    elif ! grep -q -E -- "$url([^A-Za-z0-9_/-]|\$)" "$README"; then
      readme_error "README.md does not credit the upstream $url"
    fi
  done
}

# Runs the three checks. Fails when any of them printed an error.
check_readme() {
  if [[ ! -f "$README" ]]; then
    readme_error "$README does not exist"
    return 1
  fi
  check_readme_block skills list_skills "every skill in src/skills/"
  check_readme_block agent-started agent_started_skills "the skills without disable-model-invocation: true"
  check_readme_block in-house in_house_skills "the skills that point at no upstream skill"
  check_readme_names
  check_readme_upstreams
  [[ "$readme_ok" -eq 1 ]]
}

mode=build
case "${1:-}" in
  "") ;;
  --check) mode=check ;;
  *) usage ;;
esac

OUT="$WORK/out"
mkdir -p "$OUT/skills"
for skill in $(list_skills); do
  build_skill "$skill" "$OUT"
done
write_user_manifest "$OUT"
check_references "$OUT"

if [[ "$mode" == check ]]; then
  failed=""
  if ! diff -r "$DIST_DIR" "$OUT" > "$WORK/diff.txt" 2>&1; then
    head -n 40 "$WORK/diff.txt" >&2
    failed="dist/ is out of date. Run task build-apm and commit the result."
  fi
  if ! check_readme; then
    failed="${failed:+$failed }README.md differs from src/. Fix README.md."
  fi
  if [[ -n "$failed" ]]; then die "$failed"; fi
  printf 'build-apm: dist/ is current\n'
else
  rm -rf "$DIST_DIR"
  cp -R "$OUT" "$DIST_DIR"
  printf 'built %s skills into dist/\n' "$(list_skills | wc -l | tr -d ' ')"
  if ! check_readme; then
    printf 'README.md differs from src/. Fix README.md. dist/ is built.\n' >&2
    exit 3
  fi
fi
