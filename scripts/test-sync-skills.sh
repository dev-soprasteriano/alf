#!/bin/sh
# Tests scripts/sync-skills.sh against a minimal one-skill fixture in an isolated temp repo.
set -eu

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APM="$REPO_DIR/.tools/apm/bin/apm"
if [ ! -x "$APM" ]; then
  printf 'test-sync-skills: %s not found. Install it with: sh scripts/install-tools.sh apm\n' "$APM" >&2
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export APM_HOME="$WORK/apm-home"
failures=0

fail() {
  printf 'FAIL %s: %s\n' "$1" "$2"
  failures=$((failures + 1))
}

pass() {
  printf 'ok   %s\n' "$1"
}

write_fixture_dist() {
  mkdir -p "$1/.claude-plugin" "$1/skills/demo"
  cat > "$1/.claude-plugin/plugin.json" <<'EOF'
{
  "name": "alf",
  "description": "Fixture plugin",
  "author": { "name": "test" },
  "license": "MIT"
}
EOF
  printf -- '---\nname: demo\ndescription: fixture skill\n---\nDemo skill body.\n' > "$1/skills/demo/SKILL.md"
  printf 'Fixture notes.\n' > "$1/skills/demo/NOTES.md"
}

fresh_env() {
  env -u XDG_CONFIG_HOME -u XDG_DATA_HOME -u XDG_CACHE_HOME -u XDG_STATE_HOME \
    HOME="$FRESH_HOME" APM_HOME="$FRESH_HOME/.apm" "$@"
}

REPO="$WORK/repo"
mkdir -p "$REPO/scripts" "$REPO/.tools"
cp "$REPO_DIR/scripts/sync-skills.sh" "$REPO/scripts/sync-skills.sh"
cp "$REPO_DIR/apm.yml" "$REPO/apm.yml"
write_fixture_dist "$REPO/dist"
ln -s "$REPO_DIR/.tools/apm" "$REPO/.tools/apm"

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

for root in .agents/skills .claude/skills; do
  mkdir -p "$REPO/$root/repo-only"
  printf -- '---\nname: repo-only\ndescription: local only\n---\nhi\n' > "$REPO/$root/repo-only/SKILL.md"
done

if ! out=$(sh "$REPO/scripts/sync-skills.sh" 2>&1); then
  fail "sync preserves repo-only skill" "$out"
elif [ ! -f "$REPO/.agents/skills/repo-only/SKILL.md" ] || [ ! -f "$REPO/.claude/skills/repo-only/SKILL.md" ]; then
  fail "sync preserves repo-only skill" "repo-only skill was deleted"
elif ! out=$(sh "$REPO/scripts/sync-skills.sh" --check 2>&1); then
  fail "check passes with repo-only skill" "$out"
else
  pass "repo-only skill preserved by sync and check"
fi

printf 'finder\n' > "$REPO/.agents/skills/demo/.DS_Store"
if ! out=$(sh "$REPO/scripts/sync-skills.sh" --check 2>&1); then
  fail ".DS_Store ignored by check" "$out"
else
  pass ".DS_Store ignored by check"
fi
rm -f "$REPO/.agents/skills/demo/.DS_Store"

CLONE="$WORK/fresh-clone"
FRESH_HOME="$WORK/fresh-home"
mkdir -p "$CLONE/scripts" "$CLONE/.tools" "$CLONE/.agents" "$CLONE/.claude" "$FRESH_HOME"
cp "$REPO/scripts/sync-skills.sh" "$CLONE/scripts/sync-skills.sh"
cp "$REPO/apm.yml" "$REPO/apm.lock.yaml" "$CLONE/"
cp -R "$REPO/dist" "$CLONE/dist"
cp -R "$REPO/.agents/skills" "$CLONE/.agents/skills"
cp -R "$REPO/.claude/skills" "$CLONE/.claude/skills"
ln -s "$REPO_DIR/.tools/apm" "$CLONE/.tools/apm"

fresh_env sh "$CLONE/scripts/sync-skills.sh" --record-baseline
printf '\nupdated on fresh clone\n' >> "$CLONE/dist/skills/demo/SKILL.md"
rm -f "$CLONE/dist/skills/demo/NOTES.md"
if ! out=$(fresh_env sh "$CLONE/scripts/sync-skills.sh" 2>&1); then
  fail "fresh clone updates existing skill" "$out"
elif ! cmp -s "$CLONE/dist/skills/demo/SKILL.md" "$CLONE/.agents/skills/demo/SKILL.md" ||
  ! cmp -s "$CLONE/dist/skills/demo/SKILL.md" "$CLONE/.claude/skills/demo/SKILL.md"; then
  fail "fresh clone updates existing skill" "SKILL.md does not match dist/"
elif [ ! -f "$CLONE/.agents/skills/repo-only/SKILL.md" ] || [ ! -f "$CLONE/.claude/skills/repo-only/SKILL.md" ]; then
  fail "fresh clone sync preserves repo-only skill" "repo-only skill was deleted"
elif [ -e "$CLONE/.agents/skills/demo/NOTES.md" ] || [ -e "$CLONE/.claude/skills/demo/NOTES.md" ]; then
  fail "fresh clone sync removes deleted skill file" "NOTES.md still exists"
elif ! out=$(fresh_env sh "$CLONE/scripts/sync-skills.sh" --check 2>&1); then
  fail "fresh clone check passes after sync" "$out"
else
  pass "fresh clone updates modified/deleted skill files and preserves repo-only skill"
fi

cp "$REPO/dist/skills/demo/SKILL.md" "$WORK/demo.orig"

printf '\n\342\200\256hidden\n' >> "$REPO/dist/skills/demo/SKILL.md"
if out=$(sh "$REPO/scripts/sync-skills.sh" 2>&1); then
  fail "hidden Unicode in dist blocks sync" "sync succeeded unexpectedly"
elif grep -q 'hidden' "$REPO/.agents/skills/demo/SKILL.md"; then
  fail "hidden Unicode in dist blocks sync" "poisoned file was deployed"
else
  pass "hidden Unicode in dist blocks sync before deploying"
fi
cp "$WORK/demo.orig" "$REPO/dist/skills/demo/SKILL.md"

printf '\nstale edit\n' >> "$REPO/dist/skills/demo/SKILL.md"
if out=$(sh "$REPO/scripts/sync-skills.sh" --check 2>&1); then
  fail "stale dist fails check" "check passed unexpectedly"
else
  pass "stale dist fails check"
fi
cp "$WORK/demo.orig" "$REPO/dist/skills/demo/SKILL.md"

printf '\nhand edit\n' >> "$REPO/.agents/skills/demo/SKILL.md"
if out=$(sh "$REPO/scripts/sync-skills.sh" --check 2>&1); then
  fail "hand-edited deployed skill fails check" "check passed unexpectedly"
else
  pass "hand-edited deployed skill fails check"
fi
cp "$WORK/demo.orig" "$REPO/.agents/skills/demo/SKILL.md"

if [ "$failures" -ne 0 ]; then
  printf '%s test(s) failed\n' "$failures"
  exit 1
fi
printf 'all tests passed\n'
