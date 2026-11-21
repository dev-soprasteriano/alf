#!/usr/bin/env bash
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

frontmatter() {
  awk '{ print } NR > 1 && /^---$/ { exit }' "$1"
}

body() {
  awk 'seen { print } !seen && NR > 1 && /^---$/ { seen = 1 }' "$1"
}

overlay() {
  awk -v s="$OVERLAY_START" -v e="$OVERLAY_END" '$0 == s { on = 1 } on { print } $0 == e { exit }' "$1"
}

upstream_ref() {
  grep -o '`\.\./\.\./upstream/[^`]*/SKILL\.md`' "$1" | head -n 1 \
    | sed 's#^`\.\./\.\./upstream/##; s#/SKILL\.md`$##' || true
}

list_skills() {
  local d
  for d in "$SKILLS_DIR"/*/; do
    if [[ -f "$d/SKILL.md" ]]; then
      basename "$d"
    fi
  done
}

names_for() {
  [[ -f "$DEPS_FILE" ]] || return 0
  awk -v n="$1" '
    /^#/ || !/:/ { next }
    { key = $0; sub(/:.*/, "", key); gsub(/^ +| +$/, "", key) }
    key == n { val = $0; sub(/^[^:]*:/, "", val); gsub(/^ +| +$/, "", val); print val; exit }
  ' "$DEPS_FILE"
}

deps_for() {
  names_for "$1"
}

mentions_for() {
  names_for "$1 mentions"
}

name_pattern() {
  local n="$1" pat
  pat="(^|[ (])/${n}([^A-Za-z0-9/_-]|\$)"
  pat="$pat|\`${n}\`|\"${n}\"|'${n}'|(^|[^A-Za-z0-9/_.-])${n} skill"
  printf '%s\n' "$pat"
}

build_skill() {
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

write_user_manifest() {
  local out="$1" skill
  {
    printf 'name: alf\nversion: 1.0.0\ntargets:\n  - agent-skills\n  - claude\n  - antigravity\n  - opencode\n'
    printf 'dependencies:\n  apm:\n'
    for skill in $(list_skills); do
      printf '    - %s/dist/skills/%s\n' "$ALF_REPO" "$skill"
    done
    printf '  mcp: []\n'
  } > "$out/user-apm.yml"
}

write_plugin_manifest() {
  local out="$1" url="https://github.com/$ALF_REPO"
  mkdir -p "$out/.claude-plugin"
  {
    printf '{\n  "name": "alf",\n'
    printf '  "description": "Agent skills for the core of the software development lifecycle.",\n'
    printf '  "author": { "name": "dev-soprasteriano" },\n'
    printf '  "homepage": "%s",\n  "repository": "%s",\n' "$url" "$url"
    printf '  "license": "MIT"\n}\n'
  } > "$out/.claude-plugin/plugin.json"
}

check_references() {
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

check_readme() {
  local tables skill name pin url
  tables="$(sed -n '/<!-- skills:start -->/,/<!-- skills:end -->/p' "$README")"
  for skill in $(list_skills); do
    grep -q -F "\`$skill\`" <<< "$tables" || die "README.md does not list \`$skill\` in the skills tables"
  done
  for name in $(grep -o '`[^`]*`' <<< "$tables" | tr -d '`'); do
    [[ -f "$SKILLS_DIR/$name/SKILL.md" ]] || die "README.md lists \`$name\` in the skills tables, which is not a skill"
  done
  for pin in "$UPSTREAM_DIR"/*/PIN.md; do
    url="$(sed -n '1s/^Upstream: //p' "$pin")"
    grep -q -F "$url" "$README" || die "README.md does not credit the upstream $url"
  done
}

mode=build
case "${1:-}" in
  "") ;;
  --check) mode=check ;;
  *) usage ;;
esac

check_readme

OUT="$WORK/out"
mkdir -p "$OUT/skills"
for skill in $(list_skills); do
  build_skill "$skill" "$OUT"
done
write_user_manifest "$OUT"
write_plugin_manifest "$OUT"
check_references "$OUT"

if [[ "$mode" == check ]]; then
  if ! diff -r "$DIST_DIR" "$OUT" > "$WORK/diff.txt" 2>&1; then
    head -n 40 "$WORK/diff.txt" >&2
    die "dist/ is out of date. Run task build-apm and commit the result."
  fi
  printf 'build-apm: dist/ is current\n'
else
  rm -rf "$DIST_DIR"
  cp -R "$OUT" "$DIST_DIR"
  printf 'built %s skills into dist/\n' "$(list_skills | wc -l | tr -d ' ')"
fi
