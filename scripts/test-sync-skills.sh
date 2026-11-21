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
