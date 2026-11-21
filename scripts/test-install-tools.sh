#!/bin/sh
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
failures=0

if out=$(PYTHON=sh sh "$ROOT/scripts/install-tools.sh" "../x" 2>&1); then
  echo "FAIL path traversal tool name: expected exit 2, got 0"
  failures=$((failures + 1))
else
  code=$?
  if [ "$code" -ne 2 ]; then
    echo "FAIL path traversal tool name: expected exit 2, got $code"
    failures=$((failures + 1))
  elif ! printf '%s\n' "$out" | grep -q -F "rm -rf"; then
    echo "FAIL path traversal tool name: missing rm -rf reason in '$out'"
    failures=$((failures + 1))
  else
    echo "ok   path traversal tool name rejected with exit 2"
  fi
fi

if [ "$failures" -ne 0 ]; then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all tests passed"
