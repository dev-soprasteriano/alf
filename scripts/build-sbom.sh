#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

MODE=write
case "${1:-}" in
  "") ;;
  --check) MODE=check ;;
  *)
    echo "usage: sh scripts/build-sbom.sh [--check]" >&2
    exit 2
    ;;
esac
OUT=sbom
CHECK=.tools/check-jsonschema/bin/check-jsonschema
SHIP_ALLOWED="MIT"
TAB=$(printf '\t')
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
if [ "$MODE" = check ]; then
  OUT="$WORK/sbom"
fi

if [ ! -x "$CHECK" ]; then
  echo "build-sbom: $CHECK not found. Install it with: sh scripts/install-tools.sh check-jsonschema" >&2
  exit 1
fi

sha256_of() {
  if command -v sha256sum > /dev/null 2>&1; then
    sha256sum "$1" | cut -d ' ' -f 1
  else
    shasum -a 256 "$1" | cut -d ' ' -f 1
  fi
}

rm -rf "$OUT"
mkdir -p "$OUT"
COMMIT=$(git rev-parse HEAD)

map_license() {
  case "$1" in
    MIT | "MIT License" | "The MIT License") echo MIT ;;
    "Apache-2.0" | "Apache 2.0" | "Apache License 2.0" | "Apache License, Version 2.0" | "Apache Software License") echo Apache-2.0 ;;
    "BSD-2-Clause" | "2-Clause BSD License") echo BSD-2-Clause ;;
    "BSD-3-Clause" | "3-Clause BSD License") echo BSD-3-Clause ;;
    ISC | "ISC License" | "ISC License (ISCL)") echo ISC ;;
    Unlicense | "The Unlicense (Unlicense)") echo Unlicense ;;
    "CC0-1.0" | CC0) echo CC0-1.0 ;;
    "PSF-2.0" | "Python Software Foundation License") echo PSF-2.0 ;;
    "MPL-2.0" | "Mozilla Public License 2.0 (MPL 2.0)") echo MPL-2.0 ;;
    *) ;;
  esac
}

license_status() {
  if [ "$1" = UNKNOWN ]; then
    echo unknown
    return
  fi
  status=ok
  for token in $(printf '%s' "$1" | tr '()' '  '); do
    case "$token" in
      AND | OR | WITH) continue ;;
    esac
    case " $SHIP_ALLOWED " in
      *" $token "*) ;;
      *) status=denied ;;
    esac
  done
  echo "$status"
}

: > "$WORK/wrappers.tsv"
for pin in src/upstream/*/PIN.md; do
  upstream=$(basename "$(dirname "$pin")")
  source=$(sed -n 's/^Upstream: //p' "$pin" | head -n 1)
  awk -F'|' -v up="$upstream" -v url="$source" '
    /^\|/ && $2 !~ /Skill/ && $2 !~ /---/ {
      wrapper = $6
      commit = $4
      gsub(/ /, "", wrapper)
      gsub(/ /, "", commit)
      print wrapper "|" commit "|" up "|" url
    }' "$pin" >> "$WORK/wrappers.tsv"
done

: > "$OUT/components.tsv"
for dir in dist/skills/*/; do
  name=$(basename "$dir")
  row=$(awk -F'|' -v w="$name" '$1 == w { print; exit }' "$WORK/wrappers.tsv")
  if [ -n "$row" ]; then
    IFS='|' read -r _wrapper version upstream source <<EOF
$row
EOF
    license_file="src/upstream/$upstream/LICENSE"
  else
    version="$COMMIT"
    source=""
    license_file=LICENSE
  fi
  license=$(map_license "$(head -n 1 "$license_file" | tr -d '\r')")
  if [ -z "$license" ]; then
    license=UNKNOWN
  fi
  printf '%s\t%s\t%s\t%s\n' "$name" "$version" "$license" "$source" >> "$OUT/components.tsv"
done
ROOT_LICENSE=$(map_license "$(head -n 1 LICENSE | tr -d '\r')")
if [ -z "$ROOT_LICENSE" ]; then
  ROOT_LICENSE=UNKNOWN
fi

jq -R -s -f scripts/sbom-cyclonedx.jq --arg commit "$COMMIT" --arg root_license "$ROOT_LICENSE" "$OUT/components.tsv" \
  > "$OUT/alf.cdx.json"

FINDINGS="$WORK/findings.tsv"
: > "$FINDINGS"

check_schema() {
  if ! "$CHECK" --schemafile "$1" "$2" > "$WORK/check.log" 2>&1; then
    printf 'schema\t%s\t-\tfails its schema\n' "$3" >> "$FINDINGS"
    cat "$WORK/check.log" >&2
  fi
}
check_schema tools/check-jsonschema/schemas/bom-1.6.schema.json "$OUT/alf.cdx.json" alf.cdx.json

while IFS="$TAB" read -r name version license _source; do
  status=$(license_status "$license")
  if [ "$status" != ok ]; then
    printf 'license\t%s\t%s\t%s\n' "$name" "$version" "$license" >> "$FINDINGS"
  fi
done < "$OUT/components.tsv"

cp "$FINDINGS" "$OUT/findings.tsv"
if [ -s "$FINDINGS" ]; then
  echo "build-sbom: findings (kind, package, version, detail):" >&2
  cat "$FINDINGS" >&2
  echo "build-sbom: failed. See docs/sbom.md for the checks." >&2
  exit 1
fi
if [ "$MODE" = check ]; then
  echo "build-sbom: check passed. No files written."
else
  echo "build-sbom: wrote $OUT/alf.cdx.json. Passed."
fi
