#!/bin/sh
# Scans every file in dist/ for hidden Unicode with `apm audit`, one file at a time.
# Usage: sh scripts/apm-audit-ci.sh [--staged]
#   No argument: scans every file in dist/. CI runs this.
#   --staged: scans only the staged files under dist/ that still exist. The pre-commit hook runs this.
#     Scans every file in dist/ when the staged changes alter the apm pin in APM_SOURCE below.
# Fails on any WARNING or CRITICAL finding that no entry in .apm-audit-baseline.json accepts, on any
# baseline entry without a reason, and on any apm run that exits 3 or higher or prints no valid JSON report.
# A reviewer accepts a finding by adding it to .apm-audit-baseline.json with a reason. See docs/apm-audit.md.
set -eu

APM_SOURCE="apm-cli==0.35.0"
BASELINE=".apm-audit-baseline.json"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

FINDINGS="$WORK/findings.jsonl"
BLOCKING="$WORK/blocking.tsv"
: > "$FINDINGS"
status=0

# Every baseline entry needs a file, a line, a codepoint and a non-empty reason.
if ! problems=$(jq -r '
    if type != "array" then "the baseline is not a JSON array"
    else .[] | select(type != "object" or (.file | type) != "string" or (.line | type) != "number"
      or (.codepoint | type) != "string" or (.reason | type) != "string" or (.reason | test("^\\s*$")))
      | "entry needs file, line, codepoint and a non-empty reason: \(tojson)"
    end' "$BASELINE" 2>&1) || [ -n "$problems" ]; then
  echo "apm-audit-ci: invalid $BASELINE:" >&2
  printf '%s\n' "$problems" >&2
  echo "apm-audit-ci: failed. See docs/apm-audit.md for how to fix or accept findings." >&2
  exit 1
fi

# Prints the apm pin in a revision of this script, such as HEAD:scripts/apm-audit-ci.sh, or
# :scripts/apm-audit-ci.sh for the index.
pin_at() {  # revision:path
  git show "$1" 2>/dev/null | grep -o '^APM_SOURCE="[^"]*"' | head -n 1 || true
}

# Prints the staged files under dist/ that still exist. Prints every file in dist/ when the staged changes
# alter the apm pin in this script.
staged_targets() {
  if [ "$(pin_at :scripts/apm-audit-ci.sh)" != "$(pin_at HEAD:scripts/apm-audit-ci.sh)" ]; then
    find dist -type f | sort
    return 0
  fi
  git -c core.quotePath=false diff --cached --no-renames --name-only --diff-filter=d -- dist/ |
    while IFS= read -r file; do
      if [ -f "$file" ]; then
        printf '%s\n' "$file"
      fi
    done
}

case "${1:-}" in
  "") targets=$(find dist -type f | sort) ;;
  --staged) targets=$(staged_targets) ;;
  *)
    echo "usage: sh scripts/apm-audit-ci.sh [--staged]" >&2
    exit 2
    ;;
esac

if [ -z "$targets" ]; then
  echo "apm-audit-ci: no file under dist/ changed. Nothing to scan."
  exit 0
fi

while IFS= read -r file; do
  [ -n "$file" ] || continue
  report="$WORK/report.json"
  # Exit codes 1 (CRITICAL) and 2 (WARNING) still print a report. The findings decide what blocks.
  # 3 is a configuration error. A higher code is unknown, so it fails too.
  if uvx --from "$APM_SOURCE" apm audit --file "$file" --format json > "$report" 2> "$WORK/stderr"; then
    code=0
  else
    code=$?
  fi
  if [ "$code" -gt 2 ]; then
    echo "apm-audit-ci: apm exited $code: $file" >&2
    cat "$WORK/stderr" >&2
    status=1
    continue
  fi
  if ! jq -e '.findings | type == "array"' "$report" > /dev/null 2>&1; then
    echo "apm-audit-ci: apm printed no valid JSON report (exit $code): $file" >&2
    cat "$WORK/stderr" >&2
    status=1
    continue
  fi
  # findings[].file is not always the scanned path, so tag each finding with the path passed to --file.
  jq -c --arg file "$file" '.findings[] | .file = $file' "$report" >> "$FINDINGS"
done <<EOF
$targets
EOF

# A baseline entry accepts the finding with the same file, line and codepoint. INFO never blocks. Any other
# severity blocks: the pinned apm reports only WARNING and CRITICAL besides INFO, and a severity added by a
# later version should not pass unseen.
jq -rs --slurpfile baseline "$BASELINE" '
  .[] | select(.severity != "info") | . as $f
  | select(any($baseline[0][]; .file == $f.file and .line == $f.line and .codepoint == $f.codepoint) | not)
  | [.file, .line, .codepoint, .severity, .description] | @tsv' "$FINDINGS" > "$BLOCKING"

if [ -s "$BLOCKING" ]; then
  echo "apm-audit-ci: blocking findings:" >&2
  printf 'file\tline\tcodepoint\tseverity\tdescription\n' >&2
  cat "$BLOCKING" >&2
  status=1
fi

if [ "$status" -eq 0 ]; then
  echo "apm-audit-ci: passed"
else
  echo "apm-audit-ci: failed. See docs/apm-audit.md for how to fix or accept findings." >&2
fi
exit "$status"
