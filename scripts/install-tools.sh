#!/bin/sh
set -eu

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
  case "$tool" in
    "" | *[!a-z0-9-]*)
      echo "install-tools: invalid tool name '$tool' (must be a plain folder name; becomes an rm -rf target under .tools/)" >&2
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
  cp "$lock" "$venv/requirements.txt"
done
