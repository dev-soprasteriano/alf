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

# Writes README.md with the given block contents and one extra paragraph. The fixed part holds
# what must not count as a /name: a /name in prose, and paths in a code span, a fenced block and
# a Mermaid label.
write_readme() {  # skills block, agent-started block, in-house block, extra paragraph
  write_repo README.md "# Fixture

Run \`/wrapped\` first. Logs go to /tmp, the manifest to \`~/.apm/apm.yml\`, and \`cd /tmp/\` works.

\`\`\`sh
curl -o ~/.apm/apm.yml https://example.com/alf/main/user-apm.yml
ls /usr/local/bin
\`\`\`

\`\`\`mermaid
flowchart LR
    a[\"/wrapped<br>/inhouse + /wrapped\"] --> b[\"Bundle<br>dist/skills/\"]
    b --> c[\"/tmp/x\"]
\`\`\`

<!-- readme:skills start -->

| Need | Skills |
| --- | --- |
| Any | $1 |

<!-- readme:skills end -->

<!-- readme:agent-started start -->

$2

<!-- readme:agent-started end -->

<!-- readme:in-house start -->

$3

<!-- readme:in-house end -->

$4"
}

# Rewrites README.md through a sed script.
sed_readme() {  # sed script
  sed "$1" "$REPO/README.md" > "$REPO/README.tmp"
  mv "$REPO/README.tmp" "$REPO/README.md"
}

# Passes when the check succeeds.
expect_pass() {  # name
  if out=$(bash "$REPO/scripts/build-apm.sh" --check 2>&1); then
    echo "ok   $1"
  else
    echo "FAIL $1: check failed"
    echo "$out" | sed 's/^/  /'
    failures=$((failures + 1))
  fi
}

# Passes when the check fails and its output contains the expected text.
expect_fail() {  # name, expected text
  if out=$(bash "$REPO/scripts/build-apm.sh" --check 2>&1); then
    echo "FAIL $1: check passed"
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
# The wrapper sets the field with other spacing, case and a comment. It still counts as set.
write_repo src/skills/wrapped/SKILL.md "---
name: wrapped
description: A wrapped skill.
disable-model-invocation:  True  # user only
---

Follow the skill in full at \`../../upstream/acme/wrapped/SKILL.md\`.

<!-- overlay:start -->
<!-- overlay:end -->"
# The in-house skill names the field in its body, not its frontmatter. It does not count as set.
write_repo src/skills/inhouse/SKILL.md "---
name: inhouse
description: An in-house skill.
---

Do the work. A user-only skill has this line in its frontmatter:

disable-model-invocation: true"

ALL='`wrapped`, `inhouse`'
ONE='`inhouse`'
CREDIT="Upstream: $URL"

# A build with a stale README writes dist/, then fails with status 3 and the same error lines.
write_readme '`wrapped`' "$ONE" "$ONE" "$CREDIT"
status=0
out=$(bash "$REPO/scripts/build-apm.sh" 2>&1) || status=$?
if [ "$status" -ne 3 ]; then
  echo "FAIL build with a stale README: exit status $status, want 3"
  failures=$((failures + 1))
elif [ ! -f "$REPO/dist/user-apm.yml" ]; then
  echo "FAIL build with a stale README: dist/ not written"
  failures=$((failures + 1))
else
  case "$out" in
    *'error: README.md block "skills" does not list inhouse'*) echo "ok   build with a stale README: writes dist/, then fails with status 3" ;;
    *) echo "FAIL build with a stale README: no error line"; failures=$((failures + 1)) ;;
  esac
fi

write_readme "$ALL" "$ONE" "$ONE" "$CREDIT"
if out=$(bash "$REPO/scripts/build-apm.sh" 2>&1); then
  echo "ok   build with a matching README: passes"
else
  echo "FAIL build with a matching README: build failed"
  echo "$out" | sed 's/^/  /'
  failures=$((failures + 1))
fi

write_readme "$ALL" "$ONE" "$ONE" "$CREDIT"
expect_pass "README matches src, with paths that are not skills: passes"

write_readme '`wrapped`' "$ONE" "$ONE" "$CREDIT"
expect_fail "skills block misses a skill: fails with an error" 'error: README.md block "skills" does not list inhouse'

write_readme "$ALL, \`ghost\`" "$ONE" "$ONE" "$CREDIT"
expect_fail "skills block lists an unknown name: fails" 'block "skills" lists ghost.'

write_readme "$ALL, \`task build-apm\`" "$ONE" "$ONE" "$CREDIT"
expect_fail "skills block holds a code span with a space: reported whole" 'block "skills" lists task build-apm.'

write_readme "$ALL" 'None.' "$ONE" "$CREDIT"
expect_fail "agent-started block misses a skill: fails" 'block "agent-started" does not list inhouse'

write_readme "$ALL" "$ALL" "$ONE" "$CREDIT"
expect_fail "agent-started block lists a user-only skill: fails" 'block "agent-started" lists wrapped.'

write_readme "$ALL" "$ONE" 'None.' "$CREDIT"
expect_fail "in-house block misses a skill: fails" 'block "in-house" does not list inhouse'

write_readme "$ALL" "$ONE" "$ALL" "$CREDIT"
expect_fail "in-house block lists a wrapper: fails" 'block "in-house" lists wrapped.'

write_readme "$ALL" "$ONE" "$ONE" "$CREDIT. Then run \`/renamed\`."
expect_fail "code span names a /skill that does not exist: fails" 'names /renamed, which is not a skill'

write_readme "$ALL" "$ONE" "$ONE" "$CREDIT. Then run \`/wrapped now, /argued --flag\`."
expect_fail "code span holds a /skill with other words: fails" 'names /argued, which is not a skill'

write_readme "$ALL" "$ONE" "$ONE" "$CREDIT

\`\`\`text
> /fenced my idea
\`\`\`"
expect_fail "fenced block names a /skill that does not exist: fails" 'names /fenced, which is not a skill'

write_readme "$ALL" "$ONE" "$ONE" "$CREDIT

\`\`\`mermaid
flowchart LR
    x[\"/wrapped /gone\"]
\`\`\`"
expect_fail "Mermaid label names a /skill that does not exist: fails" 'names /gone, which is not a skill'

write_readme "$ALL" "$ONE" "$ONE" "No credit."
expect_fail "README omits an upstream URL: fails" "does not credit the upstream $URL"

write_readme "$ALL" "$ONE" "$ONE" "Upstream: $URL-archive"
expect_fail "README holds only a longer URL: fails" "does not credit the upstream $URL"

write_readme "$ALL" "$ONE" "$ONE" "$CREDIT"
sed_readme '/readme:skills end/d'
expect_fail "README lacks an end marker: fails" 'must have one "<!-- readme:skills end -->" line, and has 0'

write_readme "$ALL" "$ONE" "$ONE" "$CREDIT"
sed_readme '/readme:in-house start/d'
expect_fail "README lacks a start marker: fails" 'must have one "<!-- readme:in-house start -->" line, and has 0'

write_readme "$ALL" "$ONE" "$ONE" "$CREDIT"
sed_readme 's/^<!-- readme:skills start -->$/& x/'
expect_fail "marker shares its line with other text: does not count" 'must have one "<!-- readme:skills start -->" line, and has 0'

write_readme "$ALL" "$ONE" "$ONE" "$CREDIT

<!-- readme:skills start -->

\`ghost\`

<!-- readme:skills end -->"
expect_fail "README has a block twice: fails" 'must have one "<!-- readme:skills start -->" line, and has 2'

write_readme "$ALL" "$ONE" "$ONE" "$CREDIT"
write_repo src/upstream/acme/PIN.md "# Pins"
expect_fail "PIN.md has no Upstream line: fails" 'PIN.md has no "Upstream: <url>" line'

write_readme "$ALL" "$ONE" "$ONE" "No credit."
write_repo src/upstream/acme/PIN.md "# Pins

Upstream: $URL"
expect_fail "PIN.md names its upstream below line 1: still checked" "does not credit the upstream $URL"

write_readme "$ALL" "$ONE" "$ONE" "$CREDIT"
write_repo src/upstream/acme/PIN.md "Upstream: $URL/"
expect_pass "PIN.md URL ends in a slash: the README URL without it passes"
write_repo src/upstream/acme/PIN.md "Upstream: $URL"

rm "$REPO/README.md"
expect_fail "README.md is missing: fails" 'README.md does not exist'

if [ "$failures" -eq 0 ]; then
  echo "all tests passed"
else
  echo "$failures test(s) failed"
  exit 1
fi
