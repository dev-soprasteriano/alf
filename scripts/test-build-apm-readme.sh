#!/bin/sh
set -eu

HERE=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(mktemp -d)
trap 'rm -rf "$REPO"' EXIT
cp -R "$HERE/scripts" "$HERE/src" "$REPO/"
failures=0

expect_fail() {
  if out=$(bash "$REPO/scripts/build-apm.sh" 2>&1); then
    echo "FAIL $1: build passed"
    failures=$((failures + 1))
  elif ! printf '%s\n' "$out" | grep -q -F "$2"; then
    echo "FAIL $1: want '$2', got '$out'"
    failures=$((failures + 1))
  else
    echo "ok   $1"
  fi
}

skill=$(ls "$HERE/src/skills" | head -n 1)
url=$(sed -n '1s/^Upstream: //p' "$HERE"/src/upstream/*/PIN.md | head -n 1)

sed "s/\`$skill\`//" "$HERE/README.md" > "$REPO/README.md"
expect_fail "table misses a skill" "README.md does not list \`$skill\`"

sed "s/\`$skill\`/&, \`not-a-skill\`/" "$HERE/README.md" > "$REPO/README.md"
expect_fail "table lists a name that is not a skill" "README.md lists \`not-a-skill\`"

sed "s#$url#https://example.com#g" "$HERE/README.md" > "$REPO/README.md"
expect_fail "README omits an upstream URL" "README.md does not credit the upstream $url"

if [ "$failures" -ne 0 ]; then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all tests passed"
