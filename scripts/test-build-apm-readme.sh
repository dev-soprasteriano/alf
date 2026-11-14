#!/bin/sh
# Tests the README.md check of scripts/build-apm.sh on a fixture repo with one wrapper and one
# in-house skill. Run from any directory: sh scripts/test-build-apm-readme.sh
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(mktemp -d)
trap 'rm -rf "$REPO"' EXIT
failures=0
URL=https://github.com/acme/skills

# Writes a file into the fixture repo, creating its folder.
write_repo() {  # path, content
  mkdir -p "$REPO/$(dirname "$1")"
  printf '%s\n' "$2" > "$REPO/$1"
}

# Writes README.md with the given skills table cell and credit line.
write_readme() {  # skills, credit
  write_repo README.md "# Fixture

Run \`/wrapped\` first. The manifest is at \`~/.apm/apm.yml\`.

<!-- skills:start -->

| Need | Skills |
| --- | --- |
| Any | $1 |

<!-- skills:end -->

$2"
}

# Passes when the build succeeds.
expect_pass() {  # name
  if out=$(bash "$REPO/scripts/build-apm.sh" 2>&1); then
    echo "ok   $1"
  else
    echo "FAIL $1: build failed"
    echo "$out" | sed 's/^/  /'
    failures=$((failures + 1))
  fi
}

# Passes when the build fails and its output contains the expected text.
expect_fail() {  # name, expected text
  if out=$(bash "$REPO/scripts/build-apm.sh" 2>&1); then
    echo "FAIL $1: build passed"
    failures=$((failures + 1))
    return 0
  fi
  case "$out" in
    *"$2"*) echo "ok   $1" ;;
    *)
      echo "FAIL $1"
      echo "  want: $2"
      echo "$out" | sed 's/^/  got:  /'
      failures=$((failures + 1))
      ;;
  esac
}

mkdir -p "$REPO/scripts"
cp "$HERE/build-apm.sh" "$REPO/scripts/build-apm.sh"
write_repo src/skill-dependencies.txt "# none"
write_repo src/upstream/acme/LICENSE "MIT License"
write_repo src/upstream/acme/PIN.md "Upstream: $URL"
write_repo src/upstream/acme/wrapped/SKILL.md "---
name: wrapped
description: A wrapped skill.
---

Do the work."
write_repo src/skills/wrapped/SKILL.md "---
name: wrapped
description: A wrapped skill.
---

Follow the skill in full at \`../../upstream/acme/wrapped/SKILL.md\`.

<!-- overlay:start -->
<!-- overlay:end -->"
write_repo src/skills/inhouse/SKILL.md "---
name: inhouse
description: An in-house skill.
---

Do the work."

ALL='`wrapped`, `inhouse`'

write_readme "$ALL" "Upstream: $URL"
expect_pass "README matches src: passes"

write_readme '`wrapped`' "Upstream: $URL"
expect_fail "table misses a skill: fails" 'README.md does not list `inhouse` in the skills tables'

write_readme "$ALL, \`renamed\`" "Upstream: $URL"
expect_fail "table lists a name that is not a skill: fails" 'README.md lists `renamed` in the skills tables, which is not a skill'

write_readme "$ALL" "No credit."
expect_fail "README omits an upstream URL: fails" "README.md does not credit the upstream $URL"

write_readme "$ALL" "Upstream: $URL"
sed '/skills:start/d; /skills:end/d' "$REPO/README.md" > "$REPO/README.tmp"
mv "$REPO/README.tmp" "$REPO/README.md"
expect_fail "README has no skills markers: fails" 'README.md does not list `inhouse` in the skills tables'

# --check runs the same check as a build.
write_readme "$ALL" "Upstream: $URL"
bash "$REPO/scripts/build-apm.sh" > /dev/null 2>&1
write_readme '`wrapped`' "Upstream: $URL"
if out=$(bash "$REPO/scripts/build-apm.sh" --check 2>&1); then
  echo "FAIL --check with a table that misses a skill: check passed"
  failures=$((failures + 1))
else
  case "$out" in
    *'README.md does not list `inhouse`'*) echo "ok   --check with a table that misses a skill: fails" ;;
    *) echo "FAIL --check with a table that misses a skill: wrong error"; failures=$((failures + 1)) ;;
  esac
fi

if [ "$failures" -eq 0 ]; then
  echo "all tests passed"
else
  echo "$failures test(s) failed"
  exit 1
fi
