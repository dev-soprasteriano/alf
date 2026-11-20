#!/bin/sh
# Generates the SBOM for ALF's shipped bundles in sbom/: sbom/alf.cdx.json (CycloneDX 1.6) and sbom/alf.spdx.json
# (SPDX 3.0.1). Build tools are not in the SBOM. Checks each output against its schema, and checks that each bundle's
# license is on SHIP_ALLOWED. Fails on a generation error, on an invalid file, and on a bundle license outside
# SHIP_ALLOWED. See docs/sbom.md.
# Usage: sh scripts/build-sbom.sh
# Needs jq, curl, and the tool that `sh scripts/install-tools.sh check-jsonschema` installs.
# SBOM_SPDX_SCHEMA_URL and SBOM_SPDX_SCHEMA_SHA256 override the SPDX schema source. The tests use them.
set -eu

cd "$(dirname "$0")/.."

OUT=sbom
CHECK=.tools/check-jsonschema/bin/check-jsonschema
SPDX_SCHEMA_URL="${SBOM_SPDX_SCHEMA_URL:-https://spdx.org/schema/3.0.1/spdx-json-schema.json}"
SPDX_SCHEMA_SHA256="${SBOM_SPDX_SCHEMA_SHA256:-582c64e809d5b3ef9bd0c4de13a32391b47b0284a3e8d199569fb96f649234b1}"
# The licenses a shipped bundle may carry. Add one here, with review, when a skill needs it.
SHIP_ALLOWED="MIT"
TAB=$(printf '\t')
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

if [ ! -x "$CHECK" ]; then
  echo "build-sbom: $CHECK not found. Install it with: sh scripts/install-tools.sh check-jsonschema" >&2
  exit 1
fi

# Prints the SHA-256 of a file.
sha256_of() {
  if command -v sha256sum > /dev/null 2>&1; then
    sha256sum "$1" | cut -d ' ' -f 1
  else
    shasum -a 256 "$1" | cut -d ' ' -f 1
  fi
}

# Fetches the SPDX schema and checks it against the pinned SHA-256. The schema is not kept in the repo.
SPDX_SCHEMA="$WORK/spdx-schema.json"
if ! curl -sf --max-time 60 "$SPDX_SCHEMA_URL" -o "$SPDX_SCHEMA"; then
  echo "build-sbom: could not fetch the SPDX schema from $SPDX_SCHEMA_URL" >&2
  exit 1
fi
if [ "$(sha256_of "$SPDX_SCHEMA")" != "$SPDX_SCHEMA_SHA256" ]; then
  echo "build-sbom: the SPDX schema from $SPDX_SCHEMA_URL does not match SPDX_SCHEMA_SHA256" >&2
  exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT"
COMMIT=$(git rev-parse HEAD)
CREATED=$(TZ=UTC git log -1 --format=%cd --date=format:%Y-%m-%dT%H:%M:%SZ HEAD)

# Prints the SPDX id for a license string, or nothing when the string is not on the list. A bare "BSD License"
# gets nothing: it does not say which BSD clause applies.
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

# Prints ok when every license id in the SPDX expression is on SHIP_ALLOWED, and denied when one is not. Prints
# unknown for UNKNOWN. OR is not evaluated: every alternative must be on the list.
license_status() {  # SPDX expression or UNKNOWN
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

# Bundles: one per dist/skills/<skill>/. Wrapper rows come from each upstream's PIN.md.
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

# One row per bundle: name, version, license, source. A wrapper's version is its upstream commit. An in-house
# skill's version is the ALF commit, and its license is the repository license.
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
jq -R -s -f scripts/sbom-spdx.jq --arg commit "$COMMIT" --arg created "$CREATED" --arg root_license "$ROOT_LICENSE" \
  "$OUT/components.tsv" > "$OUT/alf.spdx.json"

# Findings: kind, package, version, detail. Any finding fails the job. Licenses are decided in code, by SHIP_ALLOWED.
FINDINGS="$WORK/findings.tsv"
: > "$FINDINGS"

check_schema() {  # schema file, instance file, label
  if ! "$CHECK" --schemafile "$1" "$2" > "$WORK/check.log" 2>&1; then
    printf 'schema\t%s\t-\tfails its schema\n' "$3" >> "$FINDINGS"
    cat "$WORK/check.log" >&2
  fi
}
check_schema tools/check-jsonschema/schemas/bom-1.6.schema.json "$OUT/alf.cdx.json" alf.cdx.json
check_schema "$SPDX_SCHEMA" "$OUT/alf.spdx.json" alf.spdx.json

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
echo "build-sbom: wrote $OUT/alf.cdx.json and $OUT/alf.spdx.json. Passed."
