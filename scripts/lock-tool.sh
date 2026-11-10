#!/bin/sh
# Regenerates tools/<tool>/requirements.txt, with every dependency and its hashes, from tools/<tool>/requirements.in.
# Uses the hash-locked uv from tools/uv, installed by install-tools.sh. Targets Python 3.12, like install-tools.sh.
# Run by `task tools:lock` and by scripts/update-skillspector.sh. Commit both files after a change.
# Usage: sh scripts/lock-tool.sh <tool>
set -eu

cd "$(dirname "$0")/.."

if [ $# -ne 1 ]; then
  echo "usage: sh scripts/lock-tool.sh <tool>" >&2
  exit 2
fi
tool="$1"
case "$tool" in
  "" | *[!a-z0-9-]*)
    echo "lock-tool: invalid tool name: $tool" >&2
    exit 2
    ;;
esac
if [ ! -f "tools/$tool/requirements.in" ]; then
  echo "lock-tool: tools/$tool/requirements.in not found" >&2
  exit 2
fi

sh scripts/install-tools.sh uv
uv="$(pwd)/.tools/uv/bin/uv"
cd "tools/$tool"
"$uv" pip compile --quiet --universal --generate-hashes --python-version 3.12 --output-file requirements.txt requirements.in
