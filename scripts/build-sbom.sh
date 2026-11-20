#!/bin/sh
# Generates the SBOM for ALF in sbom/, then checks it. Writes sbom/alf.cdx.json (CycloneDX 1.6) and
# sbom/alf.spdx.json (SPDX 3.0.1). The CycloneDX schema is in tools/check-jsonschema/schemas/. The SPDX schema
# is fetched at check time and must match SPDX_SCHEMA_SHA256. It is not kept in the repo.
# A bundle license must be on SHIP_ALLOWED. A package license must be on BUILD_ALLOWED. pip-audit checks each
# tools/<tool>/requirements.txt for known vulnerabilities. Fails on a generation error, on an invalid file,
# and on each finding that .sbom-baseline.json does not accept with a reason. See docs/sbom.md.
# Usage: sh scripts/build-sbom.sh
# Needs jq, and the tools that `sh scripts/install-tools.sh apm skillspector uv check-jsonschema pip-audit`
# installs. SBOM_PYPI_BASE replaces https://pypi.org/pypi. The script reads it for a package the runner does not install.
set -eu

cd "$(dirname "$0")/.."

OUT=sbom
BASELINE=.sbom-baseline.json
CHECK=.tools/check-jsonschema/bin/check-jsonschema
PIP_AUDIT=.tools/pip-audit/bin/pip-audit
SITE=lib/python3.12/site-packages
PYPI_BASE="${SBOM_PYPI_BASE:-https://pypi.org/pypi}"
SPDX_SCHEMA_URL="${SBOM_SPDX_SCHEMA_URL:-https://spdx.org/schema/3.0.1/spdx-json-schema.json}"
SPDX_SCHEMA_SHA256="${SBOM_SPDX_SCHEMA_SHA256:-582c64e809d5b3ef9bd0c4de13a32391b47b0284a3e8d199569fb96f649234b1}"
# SHIP_ALLOWED covers bundles, which ALF distributes. BUILD_ALLOWED covers packages, which only CI runs, so it
# also takes the licenses that are acceptable only when a package is not shipped.
SHIP_ALLOWED="MIT Apache-2.0 BSD-2-Clause BSD-3-Clause ISC Unlicense CC0-1.0 PSF-2.0 0BSD Zlib"
BUILD_ALLOWED="$SHIP_ALLOWED MPL-2.0 CNRI-Python"
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
for req in tools/*/requirements.txt; do
  tool=$(basename "$(dirname "$req")")
  if [ ! -d ".tools/$tool" ]; then
    echo "build-sbom: .tools/$tool not found. Install it with: sh scripts/install-tools.sh $tool" >&2
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

# Prints the license in a metadata file: its License-Expression, else its License field, else a License
# classifier. Prints UNKNOWN when none of them is recognized.
resolve_license() {  # metadata file
  expr=$(sed -n 's/^License-Expression: //p' "$1" | tr -d '\r' | head -n 1)
  if [ -n "$expr" ]; then
    echo "$expr"
    return
  fi
  mapped=$(map_license "$(sed -n 's/^License: //p' "$1" | tr -d '\r' | head -n 1)")
  if [ -n "$mapped" ]; then
    echo "$mapped"
    return
  fi
  while IFS= read -r classifier; do
    mapped=$(map_license "${classifier#OSI Approved :: }")
    if [ -n "$mapped" ]; then
      echo "$mapped"
      return
    fi
  done <<EOF
$(sed -n 's/^Classifier: License :: //p' "$1" | tr -d '\r')
EOF
  echo UNKNOWN
}

# Prints ok when every license id in the SPDX expression is on the allow list, and denied when one is not.
# Prints unknown for UNKNOWN. OR is not evaluated: every alternative must be on the list.
license_status() {  # SPDX expression or UNKNOWN, allow list
  if [ "$1" = UNKNOWN ]; then
    echo unknown
    return
  fi
  status=ok
  for token in $(printf '%s' "$1" | tr '()' '  '); do
    case "$token" in
      AND | OR | WITH) continue ;;
    esac
    case " $2 " in
      *" $token "*) ;;
      *) status=denied ;;
    esac
  done
  echo "$status"
}

# Prints the name in PEP 503 form: lowercase, with runs of - _ . as -.
normalize_name() {  # name
  printf '%s' "$1" | sed 's/[_.]/-/g' | tr 'A-Z' 'a-z'
}

# Index of installed packages: normalized name, version, and the METADATA file of each .tools venv.
: > "$WORK/installed.tsv"
for dir in .tools/*/$SITE/*.dist-info; do
  [ -d "$dir" ] || continue
  base=$(basename "$dir" .dist-info)
  printf '%s\t%s\t%s\n' "$(normalize_name "${base%-*}")" "${base##*-}" "$dir/METADATA" >> "$WORK/installed.tsv"
done

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
  printf 'bundle\t%s\t%s\t%s\trequired\t%s\t\t\n' "$name" "$version" "$license" "$source" >> "$OUT/components.tsv"
done
ROOT_LICENSE=$(map_license "$(head -n 1 LICENSE | tr -d '\r')")
if [ -z "$ROOT_LICENSE" ]; then
  ROOT_LICENSE=UNKNOWN
fi

# Packages: each pinned line in tools/<tool>/requirements.txt, with its sha256 hashes. Markers are dropped
# here. A line pinned by URL, such as skillspector, takes its version from the wheel file name.
PARSE_LOCK='
function flush() {
  if (name != "") printf "%s\t%s\t%s\t%s\n", tool, name, version, hashes
  name = ""; version = ""; hashes = ""
}
/^[A-Za-z0-9_.-]+(==| @ )/ {
  flush()
  if ($2 == "@") {
    name = $1
    n = split($3, parts, "/")
    split(parts[n], f, "-")
    version = f[2]
  } else {
    split($1, a, "==")
    name = a[1]
    version = a[2]
  }
  next
}
/--hash=sha256:/ {
  h = $0
  sub(/.*--hash=sha256:/, "", h)
  sub(/[^0-9a-f].*/, "", h)
  hashes = hashes (hashes == "" ? "" : ",") h
}
END { flush() }
'
: > "$WORK/pins.tsv"
for req in tools/*/requirements.txt; do
  tool=$(basename "$(dirname "$req")")
  awk -v tool="$tool" "$PARSE_LOCK" "$req" >> "$WORK/pins.tsv"
done
# One row per name and version, with every tool that pins it and the union of its hashes.
jq -R -r -s '
  split("\n")
  | map(select(length > 0) | split("\t"))
  | group_by([.[1], .[2]])
  | .[]
  | [
      .[0][1],
      .[0][2],
      ([.[][0]] | unique | join(",")),
      ([.[][3] | select(length > 0) | split(",")[]] | unique | join(","))
    ]
  | join("|")
' "$WORK/pins.tsv" > "$WORK/packages.txt"

while IFS='|' read -r name version tools hashes; do
  metadata=$(awk -F'\t' -v n="$(normalize_name "$name")" -v v="$version" '$1 == n && $2 == v { print $3; exit }' "$WORK/installed.tsv")
  if [ -z "$metadata" ]; then
    # The runner's platform skips some pinned packages, such as Windows-only ones. Read their metadata from
    # PyPI for the exact pinned version.
    metadata="$WORK/pypi-$name-$version.txt"
    if ! body=$(curl -sf --max-time 60 "$PYPI_BASE/$name/$version/json"); then
      echo "build-sbom: no installed metadata and no PyPI metadata for $name $version" >&2
      exit 1
    fi
    printf '%s' "$body" | jq -r '
      "License-Expression: " + (.info.license_expression // ""),
      "License: " + (.info.license // ""),
      (.info.classifiers[]? | "Classifier: " + .)
    ' > "$metadata"
  fi
  license=$(resolve_license "$metadata")
  printf 'package\t%s\t%s\t%s\texcluded\t\t%s\t%s\n' "$name" "$version" "$license" "$tools" "$hashes" >> "$OUT/components.tsv"
done < "$WORK/packages.txt"

jq -R -s -f scripts/sbom-cyclonedx.jq --arg commit "$COMMIT" "$OUT/components.tsv" > "$OUT/alf.cdx.json"
jq -R -s -f scripts/sbom-spdx.jq --arg commit "$COMMIT" --arg created "$CREATED" --arg root_license "$ROOT_LICENSE" \
  "$OUT/components.tsv" > "$OUT/alf.spdx.json"

# Findings: kind, package, version, detail. A schema finding has no baseline entry, so it always fails.
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

while IFS="$TAB" read -r kind name version license _rest; do
  if [ "$kind" = bundle ]; then
    allowed="$SHIP_ALLOWED"
  else
    allowed="$BUILD_ALLOWED"
  fi
  status=$(license_status "$license" "$allowed")
  if [ "$status" != ok ]; then
    printf 'license\t%s\t%s\t%s\n' "$name" "$version" "$license" >> "$FINDINGS"
  fi
done < "$OUT/components.tsv"

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
    schema*)
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
  echo "build-sbom: failed. See docs/sbom.md for how to fix or accept a finding." >&2
  exit 1
fi
echo "build-sbom: wrote $OUT/alf.cdx.json and $OUT/alf.spdx.json. Accepted findings: $ACCEPTED_COUNT. Passed."
