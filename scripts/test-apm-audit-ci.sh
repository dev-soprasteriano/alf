#!/bin/sh
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/apm-audit-ci.sh"
REPO=$(mktemp -d)
REPORT_REPO=$(mktemp -d)
WORK=$(mktemp -d)
trap 'rm -rf "$REPO" "$REPORT_REPO" "$WORK"' EXIT
failures=0
CLEAN='{"exit_code": 0, "summary": {}, "findings": []}'

STUB="$WORK/apm"
cat > "$STUB" <<'EOF'
#!/bin/sh
while [ $# -gt 0 ]; do
  if [ "$1" = "--file" ] && [ $# -gt 1 ]; then
    printf '%s\n' "$2" >> "$STUB_LOG"
  fi
  shift
done
printf '%s\n' "$STUB_REPORT"
exit "$STUB_EXIT"
EOF
chmod +x "$STUB"
STUB_LOG="$WORK/scanned.txt"
export STUB_LOG

write_repo() {
  mkdir -p "$REPO/$(dirname "$1")"
  printf '%s\n' "$2" > "$REPO/$1"
}

git_repo() {
  git -C "$REPO" -c user.name=test -c user.email=test@example.com "$@"
}

normalize() {
  printf '%s\n' "$1" | sed '/^$/d' | sort
}

fail() {
  echo "FAIL $1"
  printf '  %s\n' "$2"
  failures=$((failures + 1))
}

install_stub() {
  mkdir -p "$1/.tools/apm/bin"
  cp "$STUB" "$1/.tools/apm/bin/apm"
}

RUN_IN=$REPO
run_script() {
  report=$1
  stub_exit=$2
  shift 2
  : > "$STUB_LOG"
  if out=$(cd "$RUN_IN" && STUB_REPORT="$report" STUB_EXIT="$stub_exit" sh "$SCRIPT" "$@" 2>&1); then
    code=0
  else
    code=$?
  fi
}

expect_scanned() {
  name=$1
  want=$(normalize "$2")
  shift 2
  run_script "$CLEAN" 0 "$@"
  got=$(normalize "$(cat "$STUB_LOG")")
  if [ "$code" -ne 0 ]; then
    fail "$name" "script exited $code: $out"
  elif [ "$got" != "$want" ]; then
    fail "$name" "want: $(echo "$want" | tr '\n' ' ')
  got:  $(echo "$got" | tr '\n' ' ')"
  else
    echo "ok   $name"
  fi
}

expect_result() {
  name=$1
  report=$2
  stub_exit=$3
  want_code=$4
  shift 4
  run_script "$report" "$stub_exit"
  if [ "$code" -ne "$want_code" ]; then
    fail "$name" "want exit $want_code, got $code: $out"
    return 0
  fi
  for text in "$@"; do
    if ! printf '%s\n' "$out" | grep -qF -- "$text"; then
      fail "$name" "missing \"$text\" in: $out"
      return 0
    fi
  done
  echo "ok   $name"
}

report_with() {
  severity=$1
  line=$2
  codepoint=$3
  printf '{"exit_code": 2, "summary": {}, "findings": [{"severity": "%s", "file": "SKILL.md", "line": %s, "column": 2, "codepoint": "%s", "category": "zero-width", "description": "Zero-width space"}]}' "$severity" "$line" "$codepoint"
}

git_repo init -q
write_repo .gitignore ".tools/"
write_repo tools/apm/requirements.txt "apm-cli==0.35.0"
write_repo scripts/apm-audit-ci.sh "# scan script"
write_repo dist/skills/a/SKILL.md "# A"
write_repo dist/skills/b/SKILL.md "# B"
write_repo dist/user-apm.yml "name: user"
write_repo src/skills/a/SKILL.md "# A source"
write_repo README.md "# Readme"
git_repo add -A
git_repo commit -q -m "fixture"
install_stub "$REPO"

ALL="dist/skills/a/SKILL.md
dist/skills/b/SKILL.md
dist/user-apm.yml"

expect_scanned "no argument: every file in dist/" "$ALL"

stage() {
  git_repo reset -q --hard HEAD
  git_repo clean -q -fd
  write_repo "$1" "$2"
  git_repo add "$1"
}

git_repo reset -q --hard HEAD
expect_scanned "nothing staged: nothing to scan" "" --staged

stage dist/skills/a/SKILL.md "# A, edited"
expect_scanned "dist/ file staged: that file only" "dist/skills/a/SKILL.md" --staged

stage dist/skills/c/SKILL.md "# C"
expect_scanned "new dist/ file staged: that file only" "dist/skills/c/SKILL.md" --staged

stage src/skills/a/SKILL.md "# A source, edited"
write_repo README.md "# Readme, edited"
git_repo add README.md
expect_scanned "other paths staged: nothing to scan" "" --staged

stage dist/skills/a/SKILL.md "# A, edited"
git_repo rm -q dist/skills/b/SKILL.md
expect_scanned "deleted dist/ file staged: skipped" "dist/skills/a/SKILL.md" --staged

stage dist/skills/a/SKILL.md "# A, edited"
git_repo rm -q --cached dist/skills/b/SKILL.md
expect_scanned "dist/ file deleted from the index, kept on disk: skipped" "dist/skills/a/SKILL.md" --staged

stage dist/skills/a/SKILL.md "# A, edited"
rm "$REPO/dist/skills/a/SKILL.md"
expect_scanned "staged dist/ file deleted since: skipped" "" --staged

stage scripts/apm-audit-ci.sh "# scan script, edited"
expect_scanned "scan script staged: nothing to scan" "" --staged

stage tools/apm/requirements.txt "apm-cli==0.35.1"
expect_scanned "apm lock file staged: every file in dist/" "$ALL" --staged

RUN_IN=$REPORT_REPO
mkdir -p "$REPORT_REPO/dist/skills/a"
printf '# A\n' > "$REPORT_REPO/dist/skills/a/SKILL.md"
install_stub "$REPORT_REPO"

expect_result "warning: blocks, logged with the scanned path" \
  "$(report_with warning 3 U+200B)" 2 1 \
  "dist/skills/a/SKILL.md	3	U+200B	warning	Zero-width space" "docs/apm-audit.md"
expect_result "critical: blocks" "$(report_with critical 3 U+202E)" 1 1 \
  "dist/skills/a/SKILL.md	3	U+202E	critical"
expect_result "unknown severity: blocks" "$(report_with high 3 U+200B)" 2 1 \
  "dist/skills/a/SKILL.md	3	U+200B	high"
expect_result "info: never blocks" "$(report_with info 3 U+FE0F)" 0 0 "passed"

expect_result "apm exits 3 (configuration error): fails" "$CLEAN" 3 1 "dist/skills/a/SKILL.md" "docs/apm-audit.md"
expect_result "apm exits with an unknown code: fails" "$CLEAN" 4 1 "dist/skills/a/SKILL.md" "docs/apm-audit.md"
expect_result "apm prints no valid JSON: fails" "[x] File not found" 1 1 "dist/skills/a/SKILL.md" "docs/apm-audit.md"
expect_result "apm prints JSON without findings: fails" '{"exit_code": 0}' 0 1 "dist/skills/a/SKILL.md"

rm -r "$REPORT_REPO/.tools"
expect_result "apm not installed: fails, names the install command" "$CLEAN" 0 1 "sh scripts/install-tools.sh apm"

if [ "$failures" -eq 0 ]; then
  echo "all tests passed"
else
  echo "$failures test(s) failed"
  exit 1
fi
