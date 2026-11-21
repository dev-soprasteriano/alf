#!/bin/sh
set -eu

HERE=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

if [ ! -x "$HERE/.tools/tree-sitter/bin/python" ]; then
  sh "$HERE/scripts/install-tools.sh" tree-sitter
fi
PY="$HERE/.tools/tree-sitter/bin/python"
CHECK="$HERE/scripts/check-comments.py"
failures=0

expect_pass() {
  if ! out=$("$PY" -I "$CHECK" "$2" 2>&1); then
    echo "FAIL $1: expected pass, got '$out'"
    failures=$((failures + 1))
  else
    echo "ok   $1"
  fi
}

expect_fail() {
  if out=$("$PY" -I "$CHECK" "$2" 2>&1); then
    echo "FAIL $1: expected failure, got pass"
    failures=$((failures + 1))
  elif ! printf '%s\n' "$out" | grep -q -F "$3"; then
    echo "FAIL $1: want '$3', got '$out'"
    failures=$((failures + 1))
  else
    echo "ok   $1"
  fi
}

cat > "$WORK/clean.sh" <<'EOF'
#!/usr/bin/env bash
# shellcheck disable=SC2034
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

if [ "$failures" -ne 0 ]; then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all tests passed"
