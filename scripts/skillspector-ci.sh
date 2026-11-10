#!/bin/sh
# Scans alf skills with SkillSpector, static only (no LLM).
# Usage: sh scripts/skillspector-ci.sh [--staged]
#   No argument: scans every skill folder. CI runs this.
#   --staged: scans only the skill folders of the staged files. The pre-commit hook runs this.
#     scripts/changed-skills.sh picks those folders. It also decides which changes scan every skill.
# Fails on any active MEDIUM, HIGH, or CRITICAL finding, and on any scan that errors or is incomplete.
# A reviewer accepts a finding by adding it to .skillspector-baseline.yaml with a reason.
# Runs the SkillSpector that `sh scripts/install-tools.sh skillspector` installs from
# tools/skillspector/requirements.txt.
set -eu

SKILLSPECTOR=".tools/skillspector/bin/skillspector"
BASELINE=".skillspector-baseline.yaml"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

BLOCKING="$WORK/blocking.tsv"
: > "$BLOCKING"
status=0

if [ "${1:-}" = "--staged" ]; then
  targets=$(sh scripts/changed-skills.sh --staged)
else
  targets=$(sh scripts/changed-skills.sh --all)
fi

if [ -z "$targets" ]; then
  echo "skillspector-ci: no skill folder changed. Nothing to scan."
  exit 0
fi

if [ ! -x "$SKILLSPECTOR" ]; then
  echo "skillspector-ci: $SKILLSPECTOR not found. Install it with: sh scripts/install-tools.sh skillspector" >&2
  exit 1
fi

# --baseline is rejected for recursive multi-skill scans, so each skill folder is scanned on its own.
# dist/ is not scanned here. Its bundles repeat these skills at shifted line numbers, and the
# baseline does not match them. `task ci` checks that dist/ matches a fresh build of these sources.
for skill in $targets; do
  report="$WORK/$(echo "$skill" | tr '/' '_').json"

  if ! "$SKILLSPECTOR" scan "$skill" \
      --no-llm --fail-on-incomplete --baseline "$BASELINE" \
      --format json --output "$report"; then
    echo "skillspector-ci: scan failed or incomplete: $skill" >&2
    status=1
    continue
  fi

  jq -r --arg skill "$skill" '.issues[]? | select(.severity == "MEDIUM" or .severity == "HIGH" or .severity == "CRITICAL") | [$skill, .severity, .id, .category, "\(.location.file):\(.location.start_line)"] | @tsv' \
    "$report" >> "$BLOCKING"
done

if [ -s "$BLOCKING" ]; then
  echo "skillspector-ci: active MEDIUM or higher findings (review, then accept in $BASELINE with a reason):" >&2
  printf 'skill\tseverity\tid\tcategory\tlocation\n' >&2
  cat "$BLOCKING" >&2
  status=1
fi

if [ "$status" -eq 0 ]; then
  echo "skillspector-ci: passed"
else
  echo "skillspector-ci: failed. See docs/skillspector.md for how to fix or accept findings." >&2
fi
exit "$status"
