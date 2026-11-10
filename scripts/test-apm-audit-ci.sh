#!/bin/sh
# Tests scripts/apm-audit-ci.sh in a fixture git repo, with a stub uvx on PATH in place of apm. Run from any
# directory: sh scripts/test-apm-audit-ci.sh
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/apm-audit-ci.sh"
REPO=$(mktemp -d)
REPORT_REPO=$(mktemp -d)
WORK=$(mktemp -d)
trap 'rm -rf "$REPO" "$REPORT_REPO" "$WORK"' EXIT
failures=0
PIN="apm-cli==0.35.0"
NEWPIN="apm-cli==0.35.1"
CLEAN='{"exit_code": 0, "summary": {}, "findings": []}'

# The stub uvx logs each --file argument to $STUB_LOG, prints $STUB_REPORT, and exits with $STUB_EXIT.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/uvx" <<'EOF'
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
chmod +x "$WORK/bin/uvx"
STUB_LOG="$WORK/scanned.txt"
export STUB_LOG

# Writes a file into the git repo, creating its folder. Does not stage it.
write_repo() {  # path, content
  mkdir -p "$REPO/$(dirname "$1")"
  printf '%s\n' "$2" > "$REPO/$1"
}

git_repo() {  # git arguments, run in the repo
  git -C "$REPO" -c user.name=test -c user.email=test@example.com "$@"
}

# Prints the output $1 without blank lines, sorted.
normalize() {
  printf '%s\n' "$1" | sed '/^$/d' | sort
}

fail() {  # name, detail
  echo "FAIL $1"
  printf '  %s\n' "$2"
  failures=$((failures + 1))
}

# Runs the script in the folder $RUN_IN with the stub uvx. Sets $code to its exit code, and $out to its stdout
# and stderr.
RUN_IN=$REPO
run_script() {  # report, stub exit code, script arguments...
  report=$1
  stub_exit=$2
  shift 2
  : > "$STUB_LOG"
  if out=$(cd "$RUN_IN" && PATH="$WORK/bin:$PATH" STUB_REPORT="$report" STUB_EXIT="$stub_exit" sh "$SCRIPT" "$@" 2>&1); then
    code=0
  else
    code=$?
  fi
}

# Passes when the script, with a clean report, exits 0 and scans exactly the expected files.
expect_scanned() {  # name, expected files (newline-separated), script arguments...
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

# Passes when the script, given the report and the stub exit code, exits as expected and logs every expected text.
expect_result() {  # name, report, stub exit code, expected exit code, expected texts...
  name=$1
  run_script "$2" "$3"
  want_code=$4
  shift 4
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

# Prints an apm report with one finding in SKILL.md, named by its base name as apm does.
report_with() {  # severity, line, codepoint
  printf '{"exit_code": 2, "summary": {}, "findings": [{"severity": "%s", "file": "SKILL.md", "line": %s, "column": 2, "codepoint": "%s", "category": "zero-width", "description": "Zero-width space"}]}' "$1" "$2" "$3"
}

# Fixture repo: the scan script's pin, three dist/ files and two other files.
git_repo init -q
write_repo scripts/apm-audit-ci.sh "APM_SOURCE=\"$PIN\""
write_repo dist/skills/a/SKILL.md "# A"
write_repo dist/skills/b/SKILL.md "# B"
write_repo dist/user-apm.yml "name: user"
write_repo src/skills/a/SKILL.md "# A source"
write_repo README.md "# Readme"
git_repo add -A
git_repo commit -q -m "fixture"

ALL="dist/skills/a/SKILL.md
dist/skills/b/SKILL.md
dist/user-apm.yml"

expect_scanned "no argument: every file in dist/" "$ALL"

# Each case resets the repo to the commit, then stages one change.
stage() {  # path, content
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

stage scripts/apm-audit-ci.sh "APM_SOURCE=\"$PIN\"
# a comment"
expect_scanned "scan script staged, pin unchanged: nothing to scan" "" --staged

stage scripts/apm-audit-ci.sh "# Was apm-cli==0.1.0 before.
APM_SOURCE=\"$PIN\""
expect_scanned "scan script staged, other apm-cli text above the pin: nothing to scan" "" --staged

stage scripts/apm-audit-ci.sh "APM_SOURCE=\"$NEWPIN\""
expect_scanned "scan script staged, pin changed: every file in dist/" "$ALL" --staged

# Report fixture: one dist/ file. Each case runs a report against that file.
RUN_IN=$REPORT_REPO
mkdir -p "$REPORT_REPO/dist/skills/a"
printf '# A\n' > "$REPORT_REPO/dist/skills/a/SKILL.md"

expect_result "warning: blocks, logged with the scanned path" \
  "$(report_with warning 3 U+200B)" 2 1 \
  "dist/skills/a/SKILL.md	3	U+200B	warning	Zero-width space" "docs/apm-audit.md"
expect_result "critical: blocks" "$(report_with critical 3 U+202E)" 1 1 \
  "dist/skills/a/SKILL.md	3	U+202E	critical"
expect_result "info: never blocks" "$(report_with info 3 U+FE0F)" 0 0 "passed"

expect_result "apm exits 3 (configuration error): fails" "$CLEAN" 3 1 "dist/skills/a/SKILL.md" "docs/apm-audit.md"
expect_result "apm exits with an unknown code: fails" "$CLEAN" 4 1 "dist/skills/a/SKILL.md" "docs/apm-audit.md"
expect_result "apm prints no valid JSON: fails" "[x] File not found" 1 1 "dist/skills/a/SKILL.md" "docs/apm-audit.md"
expect_result "apm prints JSON without findings: fails" '{"exit_code": 0}' 0 1 "dist/skills/a/SKILL.md"

if [ "$failures" -eq 0 ]; then
  echo "all tests passed"
else
  echo "$failures test(s) failed"
  exit 1
fi
