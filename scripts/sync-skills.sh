#!/bin/sh
# Deploys the local bundles in ./dist into .agents/skills/ and .claude/skills/ via APM,
# updating apm.lock.yaml. Run by `task build-apm` and scripts/update-upstream.sh.
# `--check` verifies in a temp copy that apm.lock.yaml and the deployed skill folders match ./dist,
# without modifying the working tree. CI runs it.
set -eu

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APM="$REPO_DIR/.tools/apm/bin/apm"

die() {
  printf 'sync-skills: %s\n' "$*" >&2
  exit 1
}

usage() {
  printf 'Usage: sh scripts/sync-skills.sh [--check]\n' >&2
  exit 2
}

mode=sync
case "${1:-}" in
  "") ;;
  --check) mode=check ;;
  *) usage ;;
esac

if [ ! -x "$APM" ]; then
  die "$APM not found. Install it with: sh scripts/install-tools.sh apm"
fi

if [ "$mode" = "sync" ]; then
  (cd "$REPO_DIR" && "$APM" install)
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

[ -f "$REPO_DIR/apm.yml" ] || die "apm.yml not found"
[ -f "$REPO_DIR/apm.lock.yaml" ] || die "apm.lock.yaml not found. Run task build-apm and commit the result."
[ -d "$REPO_DIR/dist" ] || die "dist/ not found. Run task build-apm first."

cp "$REPO_DIR/apm.yml" "$REPO_DIR/apm.lock.yaml" "$WORK/"
cp -R "$REPO_DIR/dist" "$WORK/dist"
for root in .agents/skills .claude/skills; do
  if [ -d "$REPO_DIR/$root" ]; then
    mkdir -p "$WORK/$(dirname "$root")"
    cp -R "$REPO_DIR/$root" "$WORK/$root"
  fi
done

if ! (cd "$WORK" && "$APM" install --frozen) > "$WORK/apm.out" 2>&1; then
  cat "$WORK/apm.out" >&2
  die "deployed skills or apm.lock.yaml are out of date with dist/. Run task build-apm and commit the result."
fi

for root in .agents/skills .claude/skills; do
  if [ ! -d "$REPO_DIR/$root" ]; then
    die "$root is missing. Run task build-apm and commit the result."
  fi
  if ! diff -r "$REPO_DIR/$root" "$WORK/$root" > "$WORK/diff.txt" 2>&1; then
    head -n 40 "$WORK/diff.txt" >&2
    die "$root is out of date with dist/. Run task build-apm and commit the result."
  fi
done

printf 'sync-skills: .agents/skills/ and .claude/skills/ match dist/\n'
