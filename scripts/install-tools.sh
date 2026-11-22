#!/bin/sh
# Installs CI tools into .tools/<tool>/ from tools/<tool>/requirements.txt.
# Usage: sh scripts/install-tools.sh <tool>...   Tools: the folders under tools/, such as apm or skillspector.
set -eu

# Some locked packages ship no wheel for newer Python versions.
PYTHON="${PYTHON:-python3.12}"

if [ $# -eq 0 ]; then
  echo "usage: sh scripts/install-tools.sh <tool>..." >&2
  exit 2
fi
if ! command -v "$PYTHON" > /dev/null 2>&1; then
  echo "install-tools: $PYTHON not found. Install it with: brew install python@3.12" >&2
  exit 1
fi

for tool in "$@"; do
  # The name becomes a path that is deleted below, so allow only a plain folder name.
  case "$tool" in
    "" | *[!a-z0-9-]*)
      echo "install-tools: invalid tool name: $tool" >&2
      exit 2
      ;;
  esac
  lock="tools/$tool/requirements.txt"
  venv=".tools/$tool"
  if [ ! -f "$lock" ]; then
    echo "install-tools: $lock not found" >&2
    exit 2
  fi
  if cmp -s "$lock" "$venv/requirements.txt"; then
    continue
  fi
  echo "install-tools: installing $tool from $lock"
  rm -rf "$venv"
  "$PYTHON" -m venv "$venv"
  "$venv/bin/pip" install --quiet --no-cache-dir --disable-pip-version-check --require-hashes --only-binary :all: -r "$lock"
  # Written last, so an interrupted install reinstalls on the next run.
  cp "$lock" "$venv/requirements.txt"
done
