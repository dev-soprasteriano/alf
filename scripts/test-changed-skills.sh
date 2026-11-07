#!/bin/sh
# Tests scripts/changed-skills.sh on a fixture tree. Run from any directory: sh scripts/test-changed-skills.sh
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/changed-skills.sh"
FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT
failures=0

# Writes a file into the fixture, creating its folder.
write_fixture() {  # path, content
  mkdir -p "$FIXTURE/$(dirname "$1")"
  printf '%s\n' "$2" > "$FIXTURE/$1"
}

# Passes when the script prints exactly the expected folders for the changed paths.
expect_changed() {  # name, changed paths (newline-separated), expected folders (newline-separated)
  if ! out=$(cd "$FIXTURE" && printf '%s\n' "$2" | sh "$SCRIPT"); then
    echo "FAIL $1: script exited nonzero"
    failures=$((failures + 1))
    return 0
  fi
  got=$(printf '%s\n' "$out" | sed '/^$/d' | sort)
  want=$(printf '%s\n' "$3" | sed '/^$/d' | sort)
  if [ "$got" = "$want" ]; then
    echo "ok   $1"
  else
    echo "FAIL $1"
    echo "  want: $(echo "$want" | tr '\n' ' ')"
    echo "  got:  $(echo "$got" | tr '\n' ' ')"
    failures=$((failures + 1))
  fi
}

write_fixture src/skills/inhouse/SKILL.md "# In-house skill"
write_fixture src/skills/inhouse/notes.md "Notes"

expect_changed "in-house skill file" "src/skills/inhouse/SKILL.md" "src/skills/inhouse"
expect_changed "in-house skill, other file" "src/skills/inhouse/notes.md" "src/skills/inhouse"

write_fixture src/skills/wrap-a/SKILL.md "Points at \`../../upstream/mattpocock/to-spec/SKILL.md\`."
write_fixture src/skills/wrap-x/SKILL.md "Points at \`../../upstream/mattpocock/to-spec-extra/SKILL.md\`."
write_fixture src/skills/wrap-d/SKILL.md "Points at \`../../upstream/mattpocock/removed/SKILL.md\`."
write_fixture src/skills/wrap-h/SKILL.md "Points at \`../../upstream/humanlayer/grill/SKILL.md\`."
write_fixture src/upstream/mattpocock/to-spec/SKILL.md "# To spec"
write_fixture src/upstream/mattpocock/to-spec/notes.md "Notes"
write_fixture src/upstream/mattpocock/to-spec-extra/SKILL.md "# To spec extra"
write_fixture src/upstream/mattpocock/LICENSE "MIT"
write_fixture src/upstream/humanlayer/grill/SKILL.md "# Grill"

expect_changed "upstream asset: its folder and the wrapper that links it" \
  "src/upstream/mattpocock/to-spec/notes.md" "src/upstream/mattpocock/to-spec
src/skills/wrap-a"
expect_changed "upstream skill with a longer name: no false wrapper match" \
  "src/upstream/mattpocock/to-spec-extra/SKILL.md" "src/upstream/mattpocock/to-spec-extra
src/skills/wrap-x"
expect_changed "upstream LICENSE is not a skill folder" "src/upstream/mattpocock/LICENSE" ""
expect_changed "other upstream slug" "src/upstream/humanlayer/grill/SKILL.md" "src/upstream/humanlayer/grill
src/skills/wrap-h"
expect_changed "deleted upstream skill still finds its wrapper" \
  "src/upstream/mattpocock/removed/SKILL.md" "src/skills/wrap-d"

ALL="src/skills/inhouse
src/skills/wrap-a
src/skills/wrap-d
src/skills/wrap-h
src/skills/wrap-x
src/upstream/humanlayer/grill
src/upstream/mattpocock/to-spec
src/upstream/mattpocock/to-spec-extra"

expect_changed "baseline changed: scan every skill" ".skillspector-baseline.yaml" "$ALL"
expect_changed "Taskfile changed: scan every skill" "Taskfile.yml" "$ALL"
expect_changed "scanner script changed: scan every skill" "scripts/skillspector-ci.sh" "$ALL"

write_fixture src/skills/notes/README.md "Not a skill: no SKILL.md"

expect_changed "docs and build output: nothing to scan" \
  "README.md
dist/skills/inhouse/SKILL.md
src/skill-dependencies.txt" ""
expect_changed "folder without SKILL.md: nothing to scan" "src/skills/notes/README.md" ""
expect_changed "deleted in-house skill: nothing to scan" "src/skills/gone/SKILL.md" ""
expect_changed "two files in one skill: scanned once" \
  "src/skills/inhouse/SKILL.md
src/skills/inhouse/notes.md" "src/skills/inhouse"
expect_changed "upstream file and the wrapper's own file: each folder once" \
  "src/upstream/mattpocock/to-spec/notes.md
src/skills/wrap-a/SKILL.md" "src/upstream/mattpocock/to-spec
src/skills/wrap-a"

if [ "$failures" -eq 0 ]; then
  echo "all tests passed"
else
  echo "$failures test(s) failed"
  exit 1
fi
