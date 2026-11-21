#!/bin/sh
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

(cd "$ROOT" && sh scripts/install-tools.sh tree-sitter)
PY="$ROOT/.tools/tree-sitter/bin/python"
CHECK="$ROOT/scripts/check-comments.py"
failures=0

expect_pass() {
  test_name=$1
  target=$2
  expected=${3:-}
  if ! out=$("$PY" -I "$CHECK" "$target" 2>&1); then
    echo "FAIL $test_name: expected pass, got '$out'"
    failures=$((failures + 1))
  elif [ -n "$expected" ] && ! printf '%s\n' "$out" | grep -q -F "$expected"; then
    echo "FAIL $test_name: want '$expected', got '$out'"
    failures=$((failures + 1))
  else
    echo "ok   $test_name"
  fi
}

expect_fail() {
  test_name=$1
  target=$2
  expected=$3
  if out=$("$PY" -I "$CHECK" "$target" 2>&1); then
    echo "FAIL $test_name: expected failure, got pass"
    failures=$((failures + 1))
  elif ! printf '%s\n' "$out" | grep -q -F "$expected"; then
    echo "FAIL $test_name: want '$expected', got '$out'"
    failures=$((failures + 1))
  else
    echo "ok   $test_name"
  fi
}

expect_repo_pass() {
  test_name=$1
  repo_dir=$2
  expected=$3
  shift 3
  if ! out=$(cd "$repo_dir" && "$PY" -I "$CHECK" "$@" 2>&1); then
    echo "FAIL $test_name: expected pass, got '$out'"
    failures=$((failures + 1))
  elif ! printf '%s\n' "$out" | grep -q -F "$expected"; then
    echo "FAIL $test_name: want '$expected', got '$out'"
    failures=$((failures + 1))
  else
    echo "ok   $test_name"
  fi
}

expect_repo_fail() {
  test_name=$1
  repo_dir=$2
  expected=$3
  shift 3
  if out=$(cd "$repo_dir" && "$PY" -I "$CHECK" "$@" 2>&1); then
    echo "FAIL $test_name: expected failure, got pass"
    failures=$((failures + 1))
  elif ! printf '%s\n' "$out" | grep -q -F "$expected"; then
    echo "FAIL $test_name: want '$expected', got '$out'"
    failures=$((failures + 1))
  else
    echo "ok   $test_name"
  fi
}

cat > "$WORK/clean.sh" <<'EOF'
#!/usr/bin/env bash
# shellcheck disable=SC2034 # directive reason is allowed
set -euo pipefail
ref="a/b"
trimmed="${ref#*/}"
count="$#"
printf '%s\n' "$trimmed" "$count" | sed 's#^a#b#'
awk '
  /^#/ || !/:/ { next }
  { print }
' <<< "# not a comment"
cat <<'DOC'
# markdown heading inside heredoc
DOC
EOF
expect_pass "clean shell with shebang, shellcheck, # syntax, awk, herestring, heredoc" "$WORK/clean.sh"

cat > "$WORK/bad-line.sh" <<'EOF'
#!/bin/sh
# explanatory comment
echo ok
EOF
expect_fail "full-line shell comment" "$WORK/bad-line.sh" ":2: disallowed comment: # explanatory comment"

cat > "$WORK/bad-inline.sh" <<'EOF'
#!/bin/sh
foo() {  # arg
  echo "$1"
}
EOF
expect_fail "inline shell comment" "$WORK/bad-inline.sh" ":2: disallowed comment: # arg"

cat > "$WORK/bad-shebang-line2.sh" <<'EOF'
set -eu
#!/bin/sh
EOF
expect_fail "shebang not on line 1" "$WORK/bad-shebang-line2.sh" ":2: disallowed comment: #!/bin/sh"

cat > "$WORK/broken.sh" <<'EOF'
#!/bin/sh
if [ 1 -eq 1 ]; then
  echo missing fi
EOF
expect_fail "shell parse error fails closed" "$WORK/broken.sh" "parse error: unable to parse shell file"

cat > "$WORK/clean.py" <<'EOF'
#!/usr/bin/env python3
"""Module docstring is allowed."""
x = "# hash inside string"  # noqa: E501
y = 1  # type: ignore[assignment]
z = 2  # pragma: no cover
EOF
expect_pass "clean python with shebang, docstring, string #, and directives" "$WORK/clean.py"

cat > "$WORK/bad.py" <<'EOF'
x = 1
# regular python comment
y = 2
EOF
expect_fail "python comment" "$WORK/bad.py" ":2: disallowed comment: # regular python comment"

cat > "$WORK/broken.py" <<'EOF'
x = (1 + 2
EOF
expect_fail "python tokenize error fails closed" "$WORK/broken.py" "parse error:"

printf 'plain text without shebang or extension\n' > "$WORK/mystery"
expect_fail "unclassified file fails closed" "$WORK/mystery" ":1: unclassified file"

printf '#!/usr/bin/env fish\necho hi\n' > "$WORK/fish-script"
expect_fail "fish shebang fails closed as unclassified" "$WORK/fish-script" ":1: unclassified file"

printf '.\n' > "$WORK/filter.jq"
expect_pass "explicitly unchecked .jq file prints skip notice and passes" "$WORK/filter.jq" "skipping unchecked .jq file:"

REPO="$WORK/repo"
mkdir -p "$REPO/scripts/lib" "$REPO/.githooks" "$REPO/tools/tree-sitter"
git -C "$REPO" init -q
git -C "$REPO" config user.email "test@example.com"
git -C "$REPO" config user.name "Test"
printf '#!/bin/sh\necho ok\n' > "$REPO/scripts/ok.sh"
printf '#!/bin/sh\necho hook\n' > "$REPO/.githooks/custom-hook"
printf '.\n' > "$REPO/scripts/filter.jq"
printf 'tree-sitter==0.26.1\n' > "$REPO/tools/tree-sitter/requirements.txt"
git -C "$REPO" add scripts/ok.sh scripts/filter.jq .githooks/custom-hook tools/tree-sitter/requirements.txt
git -C "$REPO" commit -q -m "init"

expect_repo_pass "full scan: checks tracked scripts and extensionless hooks, prints .jq skip" "$REPO" "skipping unchecked .jq file: scripts/filter.jq"

printf '#!/bin/sh\n# nested untracked comment\necho hi\n' > "$REPO/scripts/lib/nested.sh"
expect_repo_fail "full scan: catches nested untracked script" "$REPO" "scripts/lib/nested.sh:2: disallowed comment: # nested untracked comment"
rm "$REPO/scripts/lib/nested.sh"

TAB_SCRIPT=$(printf 'scripts/a\tb.sh')
printf '#!/bin/sh\n# tab filename comment\necho hi\n' > "$REPO/$TAB_SCRIPT"
expect_repo_fail "full scan: catches comment in tab-named script" "$REPO" ":2: disallowed comment: # tab filename comment"
git -C "$REPO" add "$TAB_SCRIPT"
expect_repo_fail "staged: catches comment in tab-named script" "$REPO" ":2: disallowed comment: # tab filename comment" --staged
git -C "$REPO" reset -q HEAD -- "$TAB_SCRIPT"
rm "$REPO/$TAB_SCRIPT"

printf '#!/bin/sh\n# hook comment\necho hook\n' > "$REPO/.githooks/custom-hook"
expect_repo_fail "full scan: catches comment in extensionless hook" "$REPO" ".githooks/custom-hook:2: disallowed comment: # hook comment"
git -C "$REPO" checkout -q -- .githooks/custom-hook

printf 'mystery\n' > "$REPO/scripts/unknown-file"
expect_repo_fail "full scan: fails closed on unclassified file" "$REPO" "scripts/unknown-file:1: unclassified file"
rm "$REPO/scripts/unknown-file"

expect_repo_pass "staged: nothing staged" "$REPO" "no staged script changed" --staged

printf '#!/bin/sh\necho clean\n' > "$REPO/scripts/ok.sh"
git -C "$REPO" add scripts/ok.sh
printf '#!/bin/sh\n# unstaged comment\necho clean\n' > "$REPO/scripts/ok.sh"
expect_repo_pass "staged: checks index blob, ignores unstaged working-tree comment" "$REPO" "1 staged file(s) clean" --staged

git -C "$REPO" add scripts/ok.sh
expect_repo_fail "staged: catches staged comment" "$REPO" "scripts/ok.sh:2: disallowed comment: # unstaged comment" --staged

git -C "$REPO" reset -q HEAD scripts/ok.sh
git -C "$REPO" checkout -q -- scripts/ok.sh
printf '#!/bin/sh\n# existing comment\necho bad\n' > "$REPO/scripts/old.sh"
git -C "$REPO" add scripts/old.sh
git -C "$REPO" commit -q -m "add old"
printf 'tree-sitter==0.26.1\n' >> "$REPO/tools/tree-sitter/requirements.txt"
git -C "$REPO" add tools/tree-sitter/requirements.txt
expect_repo_fail "staged: lockfile change triggers full scan" "$REPO" "scripts/old.sh:2: disallowed comment: # existing comment" --staged

if [ "$failures" -ne 0 ]; then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all tests passed"
