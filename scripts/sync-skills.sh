#!/bin/sh
# Deploys the local bundles in ./dist into .agents/skills/ and .claude/skills/ via APM,
# updating apm.lock.yaml. Run by `task build-apm` and scripts/update-upstream.sh.
# `--check` verifies in a temp root that apm.lock.yaml and the deployed skill folders match ./dist,
# without modifying the working tree or ~/.apm/deployment-receipts/. CI runs it.
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

[ -x "$APM" ] || die "$APM not found. Install it with: sh scripts/install-tools.sh apm"
[ -f "$REPO_DIR/apm.yml" ] || die "apm.yml not found"
[ -d "$REPO_DIR/dist" ] || die "dist/ not found. Run task build-apm first."

cd "$REPO_DIR"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

tmp_apm() {
  if ! APM_HOME="$WORK/apm-home" "$APM" install "$@" > "$WORK/apm.out" 2>&1; then
    cat "$WORK/apm.out" >&2
    return 1
  fi
}

if [ "$mode" = "sync" ]; then
  # Pre-flight into an empty root without --force so APM still blocks critical hidden-character
  # findings before --force overwrites existing repo files that lack local receipts.
  tmp_apm --root "$WORK/preflight" || die "pre-flight apm install failed (see output above); refusing to deploy ./dist"
  exec "$APM" install --force
fi

[ -f apm.lock.yaml ] || die "apm.lock.yaml not found. Run task build-apm and commit the result."
cp apm.lock.yaml "$WORK/"
for root in .agents/skills .claude/skills; do
  [ -d "$root" ] || die "$root is missing. Run task build-apm and commit the result."
  mkdir -p "$WORK/${root%/*}"
  cp -R "$root" "$WORK/$root"
done
find "$WORK" -name '.DS_Store' -delete

tmp_apm --frozen --root "$WORK" || die "apm install --frozen failed (see output above). If dist/ changed, run task build-apm and commit the result."

for root in .agents/skills .claude/skills; do
  if ! diff -r -x .DS_Store "$root" "$WORK/$root" > "$WORK/diff.txt" 2>&1; then
    head -n 40 "$WORK/diff.txt" >&2
    die "$root differs from dist/. Run task build-apm, or remove stray files inside deployed skill folders."
  fi
done

printf 'sync-skills: .agents/skills/ and .claude/skills/ match dist/\n'
