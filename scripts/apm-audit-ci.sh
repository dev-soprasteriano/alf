#!/bin/sh
set -eu

APM=".tools/apm/bin/apm"
LOCK="tools/apm/requirements.txt"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

FINDINGS="$WORK/findings.jsonl"
BLOCKING="$WORK/blocking.tsv"
: > "$FINDINGS"
status=0

staged_targets() {
  if ! git diff --cached --quiet -- "$LOCK"; then
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

if [ ! -x "$APM" ]; then
  echo "apm-audit-ci: $APM not found. Install it with: sh scripts/install-tools.sh apm" >&2
  exit 1
fi

while IFS= read -r file; do
  [ -n "$file" ] || continue
  report="$WORK/report.json"
  if "$APM" audit --file "$file" --format json > "$report" 2> "$WORK/stderr"; then
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
  jq -c --arg file "$file" '.findings[] | .file = $file' "$report" >> "$FINDINGS"
done <<EOF
$targets
EOF

jq -rs '.[] | select(.severity != "info") | [.file, .line, .codepoint, .severity, .description] | @tsv' \
  "$FINDINGS" > "$BLOCKING"

if [ -s "$BLOCKING" ]; then
  echo "apm-audit-ci: blocking findings:" >&2
  printf 'file\tline\tcodepoint\tseverity\tdescription\n' >&2
  cat "$BLOCKING" >&2
  status=1
fi

if [ "$status" -eq 0 ]; then
  echo "apm-audit-ci: passed"
else
  echo "apm-audit-ci: failed. See docs/apm-audit.md for how to fix findings." >&2
fi
exit "$status"
