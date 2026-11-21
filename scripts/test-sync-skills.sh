#!/bin/sh
# Tests scripts/sync-skills.sh in an isolated temp repo.
set -eu

HERE="$(cd "$(dirname "$0")/.." && pwd)"
APM="$HERE/.tools/apm/bin/apm"
if [ ! -x "$APM" ]; then
  sh "$HERE/scripts/install-tools.sh" apm
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

failures=0

fail() {
  printf 'FAIL %s: %s\n' "$1" "$2"
  failures=$((failures + 1))
}

pass() {
  printf 'ok   %s\n' "$1"
}

REPO="$WORK/repo"
mkdir -p "$REPO/scripts" "$REPO/.tools"
cp "$HERE/scripts/sync-skills.sh" "$REPO/scripts/sync-skills.sh"
cp "$HERE/apm.yml" "$REPO/apm.yml"
cp -R "$HERE/dist" "$REPO/dist"
ln -s "$HERE/.tools/apm" "$REPO/.tools/apm"

if ! out=$(sh "$REPO/scripts/sync-skills.sh" 2>&1); then
  fail "initial sync" "$out"
else
  pass "initial sync"
fi

if ! out=$(sh "$REPO/scripts/sync-skills.sh" --check 2>&1); then
  fail "clean check" "$out"
else
  pass "clean check"
fi

mkdir -p "$REPO/.agents/skills/repo-only" "$REPO/.claude/skills/repo-only"
printf -- '---\nname: repo-only\ndescription: local only\n---\nhi\n' > "$REPO/.agents/skills/repo-only/SKILL.md"
printf -- '---\nname: repo-only\ndescription: local only\n---\nhi\n' > "$REPO/.claude/skills/repo-only/SKILL.md"

if ! out=$(sh "$REPO/scripts/sync-skills.sh" 2>&1); then
  fail "sync preserves repo-only skill" "$out"
elif [ ! -f "$REPO/.agents/skills/repo-only/SKILL.md" ] || [ ! -f "$REPO/.claude/skills/repo-only/SKILL.md" ]; then
  fail "sync preserves repo-only skill" "repo-only skill was deleted"
elif ! out=$(sh "$REPO/scripts/sync-skills.sh" --check 2>&1); then
  fail "check passes with repo-only skill" "$out"
else
  pass "repo-only skill preserved by sync and check"
fi

printf 'finder\n' > "$REPO/.agents/skills/pr/.DS_Store"
if ! out=$(sh "$REPO/scripts/sync-skills.sh" --check 2>&1); then
  fail ".DS_Store ignored by check" "$out"
else
  pass ".DS_Store ignored by check"
fi
rm -f "$REPO/.agents/skills/pr/.DS_Store"

CLONE="$WORK/fresh-clone"
FRESH_HOME="$WORK/fresh-home"
mkdir -p "$CLONE/scripts" "$CLONE/.tools" "$CLONE/.agents" "$CLONE/.claude" "$FRESH_HOME"
cp "$REPO/scripts/sync-skills.sh" "$CLONE/scripts/sync-skills.sh"
cp "$REPO/apm.yml" "$REPO/apm.lock.yaml" "$CLONE/"
cp -R "$REPO/dist" "$CLONE/dist"
cp -R "$REPO/.agents/skills" "$CLONE/.agents/skills"
cp -R "$REPO/.claude/skills" "$CLONE/.claude/skills"
ln -s "$HERE/.tools/apm" "$CLONE/.tools/apm"

printf '\nupdated on fresh clone\n' >> "$CLONE/dist/skills/pr/SKILL.md"
rm -f "$CLONE/dist/skills/pr/CREDITS.md"
if ! out=$(HOME="$FRESH_HOME" sh "$CLONE/scripts/sync-skills.sh" 2>&1); then
  fail "fresh clone without receipts can update existing skill" "$out"
elif ! HOME="$FRESH_HOME" sh "$CLONE/scripts/sync-skills.sh" --check > /dev/null 2>&1; then
  fail "fresh clone check passes after sync" "check failed after sync"
elif [ ! -f "$CLONE/.agents/skills/repo-only/SKILL.md" ] || [ ! -f "$CLONE/.claude/skills/repo-only/SKILL.md" ]; then
  fail "fresh clone sync preserves repo-only skill" "repo-only skill was deleted"
elif [ -e "$CLONE/.agents/skills/pr/CREDITS.md" ]; then
  fail "fresh clone sync removes deleted skill file" "CREDITS.md still exists"
else
  pass "fresh clone without receipts updates modified/deleted skill files and preserves repo-only skill"
fi

printf '\nstale edit\n' >> "$REPO/dist/skills/pr/SKILL.md"
if out=$(sh "$REPO/scripts/sync-skills.sh" --check 2>&1); then
  fail "stale dist fails check" "check passed unexpectedly"
else
  pass "stale dist fails check"
fi
cp "$HERE/dist/skills/pr/SKILL.md" "$REPO/dist/skills/pr/SKILL.md"

printf '\nhand edit\n' >> "$REPO/.agents/skills/pr/SKILL.md"
if out=$(sh "$REPO/scripts/sync-skills.sh" --check 2>&1); then
  fail "hand-edited deployed skill fails check" "check passed unexpectedly"
else
  pass "hand-edited deployed skill fails check"
fi
cp "$REPO/dist/skills/pr/SKILL.md" "$REPO/.agents/skills/pr/SKILL.md"

cp "$REPO/apm.lock.yaml" "$WORK/lock.orig"
sed 's/^apm_version: .*/apm_version: 0.35.0/' "$WORK/lock.orig" > "$REPO/apm.lock.yaml"
if ! out=$(sh "$REPO/scripts/sync-skills.sh" --check 2>&1); then
  fail "older apm_version passes check" "$out"
elif ! grep -q '^apm_version: 0\.35\.0$' "$REPO/apm.lock.yaml"; then
  fail "older apm_version passes check" "check mutated apm.lock.yaml"
else
  pass "older apm_version passes check without mutating apm.lock.yaml"
fi

if [ "$failures" -ne 0 ]; then
  printf '%s test(s) failed\n' "$failures"
  exit 1
fi
printf 'all tests passed\n'
