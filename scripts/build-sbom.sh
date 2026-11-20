#!/bin/sh
# Generates the SBOM for ALF's shipped bundles in sbom/: sbom/alf.cdx.json (CycloneDX 1.6) and sbom/alf.spdx.json
# (SPDX 3.0.1). Build tools are not in the SBOM. Checks each output against its schema, checks that each bundle's
# license is on SHIP_ALLOWED, and runs pip-audit on each tools/<tool>/requirements.txt. Fails on a generation error,
# on an invalid file, on a bundle license outside SHIP_ALLOWED, and on each finding that .sbom-baseline.json does not
# accept with a reason. See docs/sbom.md.
# Usage: sh scripts/build-sbom.sh
# Needs jq, curl, and the tools that `sh scripts/install-tools.sh check-jsonschema pip-audit` installs.
# SBOM_SPDX_SCHEMA_URL and SBOM_SPDX_SCHEMA_SHA256 override the SPDX schema source. The tests use them.
set -eu

cd "$(dirname "$0")/.."

OUT=sbom
BASELINE=.sbom-baseline.json
CHECK=.tools/check-jsonschema/bin/check-jsonschema
PIP_AUDIT=.tools/pip-audit/bin/pip-audit
SPDX_SCHEMA_URL="${SBOM_SPDX_SCHEMA_URL:-https://spdx.org/schema/3.0.1/spdx-json-schema.json}"
SPDX_SCHEMA_SHA256="${SBOM_SPDX_SCHEMA_SHA256:-582c64e809d5b3ef9bd0c4de13a32391b47b0284a3e8d199569fb96f649234b1}"
# The licenses a shipped bundle may carry. Add one here, with review, when a skill needs it.
SHIP_ALLOWED="MIT"
TAB=$(printf '\t')
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

if [ ! -f "$BASELINE" ]; then
  echo "build-sbom: $BASELINE not found" >&2
  exit 1
fi
for tool in "$CHECK" "$PIP_AUDIT"; do
  if [ ! -x "$tool" ]; then
    echo "build-sbom: $tool not found. Install it with: sh scripts/install-tools.sh check-jsonschema pip-audit" >&2
    exit 1
  fi
done

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
mkdir -p "$OUT/audit"
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

# Findings: kind, package, version, detail. A schema or license finding has no baseline entry, so it always fails:
# licenses are decided in code, by SHIP_ALLOWED.
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

# pip-audit reads each tool's pins, with environment markers removed, so platform-only pins are checked too.
for req in tools/*/requirements.txt; do
  tool=$(basename "$(dirname "$req")")
  sed 's/ ; [^\\]*//' "$req" > "$WORK/$tool.txt"
  code=0
  "$PIP_AUDIT" -r "$WORK/$tool.txt" --no-deps --disable-pip -f json -o "$OUT/audit/$tool.json" > "$WORK/audit.log" 2>&1 || code=$?
  # Exit 1 means pip-audit found vulnerabilities. Any other failure is a generation error.
  if [ "$code" -gt 1 ]; then
    echo "build-sbom: pip-audit failed on tools/$tool (exit $code)" >&2
    cat "$WORK/audit.log" >&2
    exit 1
  fi
  jq -r '.dependencies[] | select(.vulns | length > 0) | .name as $n | .version as $v | .vulns[] | ["vulnerability", $n, $v, .id] | join("\t")' \
    "$OUT/audit/$tool.json" | sort -u >> "$FINDINGS"
done

# The baseline accepts a finding only with a reason.
if ! jq -e '.accepted | type == "array"' "$BASELINE" > /dev/null; then
  echo "build-sbom: $BASELINE has no accepted array" >&2
  exit 1
fi
if [ -n "$(jq -r '.accepted[] | select((.reason // "") == "") | .package' "$BASELINE")" ]; then
  echo "build-sbom: $BASELINE has an entry without a reason" >&2
  exit 1
fi
jq -r '.accepted[] | [.kind, .package, .version, (.license // .id // "")] | join("\t")' "$BASELINE" > "$WORK/accepted.tsv"

UNACCEPTED="$WORK/unaccepted.tsv"
: > "$UNACCEPTED"
ACCEPTED_COUNT=0
while IFS= read -r finding; do
  case "$finding" in
    schema* | license*)
      echo "$finding" >> "$UNACCEPTED"
      ;;
    *)
      if grep -qxF "$finding" "$WORK/accepted.tsv"; then
        ACCEPTED_COUNT=$((ACCEPTED_COUNT + 1))
      else
        echo "$finding" >> "$UNACCEPTED"
      fi
      ;;
  esac
done < "$FINDINGS"
cp "$FINDINGS" "$OUT/findings.tsv"

if [ -s "$UNACCEPTED" ]; then
  echo "build-sbom: findings not accepted by $BASELINE (kind, package, version, detail):" >&2
  cat "$UNACCEPTED" >&2
  echo "build-sbom: failed. See docs/sbom.md for how to accept a finding." >&2
  exit 1
fi
echo "build-sbom: wrote $OUT/alf.cdx.json and $OUT/alf.spdx.json. Accepted findings: $ACCEPTED_COUNT. Passed."
