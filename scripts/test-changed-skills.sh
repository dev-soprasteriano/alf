#!/bin/sh
# Tests scripts/changed-skills.sh on a fixture tree and a fixture git repo. Run from any directory:
# sh scripts/test-changed-skills.sh
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/changed-skills.sh"
FIXTURE=$(mktemp -d)
REPO=$(mktemp -d)
trap 'rm -rf "$FIXTURE" "$REPO"' EXIT
failures=0

# Writes a file into the fixture, creating its folder.
write_fixture() {  # path, content
  mkdir -p "$FIXTURE/$(dirname "$1")"
  printf '%s\n' "$2" > "$FIXTURE/$1"
}

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

# Passes when the output matches the expected folders.
check() {  # name, output, expected folders (newline-separated)
  got=$(normalize "$2")
  want=$(normalize "$3")
  if [ "$got" = "$want" ]; then
    echo "ok   $1"
  else
    echo "FAIL $1"
    echo "  want: $(echo "$want" | tr '\n' ' ')"
    echo "  got:  $(echo "$got" | tr '\n' ' ')"
    failures=$((failures + 1))
  fi
}

# Passes when the script, given the changed paths on stdin, prints the expected folders.
expect_changed() {  # name, changed paths (newline-separated), expected folders (newline-separated)
  if ! out=$(cd "$FIXTURE" && printf '%s\n' "$2" | sh "$SCRIPT"); then
    echo "FAIL $1: script exited nonzero"
    failures=$((failures + 1))
    return 0
  fi
  check "$1" "$out" "$3"
}

# Passes when the script, run with --staged in the git repo, prints the expected folders.
expect_staged() {  # name, expected folders (newline-separated)
  if ! out=$(cd "$REPO" && sh "$SCRIPT" --staged); then
    echo "FAIL $1: script exited nonzero"
    failures=$((failures + 1))
    return 0
  fi
  check "$1" "$out" "$2"
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
expect_changed "SkillSpector lock file changed: scan every skill" "tools/skillspector/requirements.txt" "$ALL"
expect_changed "Taskfile.yml alone, on the stdin path: no skill folder" "Taskfile.yml" ""
expect_changed "scanner script alone, on the stdin path: no skill folder" "scripts/skillspector-ci.sh" ""

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

# Git repo for --staged: one skill, one other skill, the Taskfile, the scan script, the lock file and the baseline.
git_repo init -q
write_repo Taskfile.yml "version: '3'"
write_repo scripts/skillspector-ci.sh "# scan script"
write_repo tools/skillspector/requirements.txt "skillspector @ https://example.com/skillspector-2.13.4-py3-none-any.whl"
write_repo .skillspector-baseline.yaml "version: 2"
write_repo src/skills/inhouse/SKILL.md "# In-house skill"
write_repo src/skills/other/SKILL.md "# Other skill"
git_repo add -A
git_repo commit -q -m "fixture"

# Each case resets the repo to the commit, then stages one change.
stage() {  # path, content
  git_repo reset -q --hard HEAD
  write_repo "$1" "$2"
  git_repo add "$1"
}

git_repo reset -q --hard HEAD
expect_staged "nothing staged: nothing to scan" ""

stage src/skills/inhouse/SKILL.md "# In-house skill, edited"
expect_staged "skill file staged: its folder only" "src/skills/inhouse"

stage Taskfile.yml "version: '3'
# a comment"
expect_staged "Taskfile.yml staged: nothing to scan" ""

stage scripts/skillspector-ci.sh "# scan script, edited"
expect_staged "scan script staged: nothing to scan" ""

stage tools/skillspector/requirements.txt "skillspector @ https://example.com/skillspector-2.13.5-py3-none-any.whl"
expect_staged "SkillSpector lock file staged: every skill" "src/skills/inhouse
src/skills/other"

stage .skillspector-baseline.yaml "version: 2
rules: []"
expect_staged "baseline staged: every skill" "src/skills/inhouse
src/skills/other"

if [ "$failures" -eq 0 ]; then
  echo "all tests passed"
else
  echo "$failures test(s) failed"
  exit 1
fi
