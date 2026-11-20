#!/bin/sh
# Tests scripts/build-sbom.sh in fixture git repos. The fixtures have stub check-jsonschema and pip-audit tools, and a
# file:// copy of the SPDX schema. No network. Run from any directory: sh scripts/test-build-sbom.sh
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
# The SPDX schema is fetched by URL. The tests use a fixture file with its own SHA-256, so they run offline.
printf '{"title": "fixture"}\n' > "$WORK/spdx-schema.json"
SBOM_SPDX_SCHEMA_URL="file://$WORK/spdx-schema.json"
SBOM_SPDX_SCHEMA_SHA256=$(if command -v sha256sum > /dev/null 2>&1; then sha256sum "$WORK/spdx-schema.json" | cut -d ' ' -f 1; else shasum -a 256 "$WORK/spdx-schema.json" | cut -d ' ' -f 1; fi)
export SBOM_SPDX_SCHEMA_URL SBOM_SPDX_SCHEMA_SHA256
failures=0
UPSTREAM_COMMIT=1111111111111111111111111111111111111111

# Stub check-jsonschema. It fails when STUB_SCHEMA_FAIL is set. Otherwise it passes any instance that parses as JSON.
STUB_CHECK="$WORK/check-jsonschema"
cat > "$STUB_CHECK" <<'EOF'
#!/bin/sh
if [ -n "${STUB_SCHEMA_FAIL:-}" ]; then
  echo "stub: schema validation failed" >&2
  exit 1
fi
for last; do :; done
jq -e . "$last" > /dev/null
EOF

# Stub pip-audit. It writes $STUB_AUDIT_JSON to the -o file. It exits 1 when that report lists a vulnerability,
# and 2 when STUB_AUDIT_FAIL is set.
STUB_AUDIT="$WORK/pip-audit"
cat > "$STUB_AUDIT" <<'EOF'
#!/bin/sh
if [ -n "${STUB_AUDIT_FAIL:-}" ]; then
  echo "stub: pip-audit failed" >&2
  exit 2
fi
out=""
while [ $# -gt 0 ]; do
  if [ "$1" = "-o" ]; then
    out="$2"
  fi
  shift
done
printf '%s\n' "$STUB_AUDIT_JSON" > "$out"
if jq -e '[.dependencies[].vulns | length] | add > 0' "$out" > /dev/null; then
  exit 1
fi
exit 0
EOF
chmod +x "$STUB_CHECK" "$STUB_AUDIT"

fail() {  # name, detail
  echo "FAIL $1"
  printf '  %s\n' "$2"
  failures=$((failures + 1))
}

# Builds a fixture repo in $1 with one wrapped upstream bundle and one in-house bundle. Three tool pins are in
# tools/*/requirements.txt. Test cases edit the fixture afterwards.
make_fixture() {  # dir
  dir="$1"
  mkdir -p "$dir/scripts" "$dir/src/upstream/example" "$dir/dist/skills/wrapped" "$dir/dist/skills/inhouse"
  cp "$HERE/build-sbom.sh" "$HERE/sbom-cyclonedx.jq" "$HERE/sbom-spdx.jq" "$dir/scripts/"
  mkdir -p "$dir/.tools/check-jsonschema/bin" "$dir/.tools/pip-audit/bin"
  cp "$STUB_CHECK" "$dir/.tools/check-jsonschema/bin/check-jsonschema"
  cp "$STUB_AUDIT" "$dir/.tools/pip-audit/bin/pip-audit"

  printf 'Upstream: https://github.com/example/skills\n\n| Skill | Upstream path | Commit | Pinned | Wrapper |\n| --- | --- | --- | --- | --- |\n| wrapped | skills/wrapped | %s | no | wrapped |\n' \
    "$UPSTREAM_COMMIT" > "$dir/src/upstream/example/PIN.md"
  printf 'MIT License\n\nCopyright (c) Example\n' > "$dir/src/upstream/example/LICENSE"
  printf 'MIT License\n\nCopyright (c) ALF\n' > "$dir/LICENSE"
  printf '# wrapped\n' > "$dir/dist/skills/wrapped/SKILL.md"
  printf '# inhouse\n' > "$dir/dist/skills/inhouse/SKILL.md"

  mkdir -p "$dir/tools/apm" "$dir/tools/uv" "$dir/tools/skillspector"
  cat > "$dir/tools/apm/requirements.txt" <<'EOF'
alpha==1.0.0 ; sys_platform != 'win32' \
    --hash=sha256:aaaa \
    --hash=sha256:bbbb
    # via -r requirements.in
shared==2.0 \
    --hash=sha256:cccc
EOF
  cat > "$dir/tools/uv/requirements.txt" <<'EOF'
shared==2.0 \
    --hash=sha256:dddd
EOF
  cat > "$dir/tools/skillspector/requirements.txt" <<'EOF'
skillspector @ https://example.invalid/skillspector-2.13.4-py3-none-any.whl \
    --hash=sha256:eeee
EOF

  printf '{\n  "accepted": []\n}\n' > "$dir/.sbom-baseline.json"
  git -C "$dir" init -q
  git -C "$dir" -c user.name=test -c user.email=test@example.com commit -q --allow-empty -m fixture
}

# Runs the script in fixture $1. Sets $code to its exit code, and $out to its stdout and stderr.
run_in() {  # dir
  code=0
  out=$(cd "$1" && sh scripts/build-sbom.sh 2>&1) || code=$?
}

expect_code() {  # name, want, got
  if [ "$2" != "$3" ]; then
    fail "$1" "exit $3, want $2. Output: $out"
  fi
}

expect_line() {  # name, line of the output, with tabs
  if ! printf '%s\n' "$out" | grep -qxF "$2"; then
    fail "$1" "missing output line: $2. Output: $out"
  fi
}

expect_json() {  # name, dir, jq filter that must be true in sbom/alf.cdx.json
  if ! jq -e "$3" "$2/sbom/alf.cdx.json" > /dev/null 2>&1; then
    fail "$1" "sbom/alf.cdx.json does not satisfy: $3"
  fi
}

# Default: no vulnerabilities, no stub failures.
export STUB_AUDIT_JSON='{"dependencies":[]}'

# Case 1: both bundles pass, and no vulnerability is found. Both files list only the two bundles.
d="$WORK/happy"
make_fixture "$d"
head_sha=$(git -C "$d" rev-parse HEAD)
unset STUB_SCHEMA_FAIL STUB_AUDIT_FAIL
run_in "$d"
expect_code "happy path exits 0" 0 "$code"
if [ ! -f "$d/sbom/alf.spdx.json" ]; then
  fail "happy: SPDX file is written" "sbom/alf.spdx.json is missing"
fi
expect_json "happy: only the two bundles are listed" "$d" '.components | length == 2'
expect_json "happy: wrapped bundle has its upstream commit" "$d" \
  '.components[] | select(.name == "wrapped") | .version == "1111111111111111111111111111111111111111"'
expect_json "happy: in-house bundle has the ALF commit" "$d" \
  ".components[] | select(.name == \"inhouse\") | .version == \"$head_sha\""
if ! jq -e '[.["@graph"][] | select(.type == "software_Package") | .name] | sort == ["alf", "inhouse", "wrapped"]' \
  "$d/sbom/alf.spdx.json" > /dev/null 2>&1; then
  fail "happy: SPDX lists the bundles and the root only" "$(jq -c '[.["@graph"][] | select(.type == "software_Package") | .name]' "$d/sbom/alf.spdx.json")"
fi

# Case 2: a bundle under MPL-2.0 fails, because the ship list does not allow it.
d="$WORK/bundle-mpl"
make_fixture "$d"
printf 'Mozilla Public License 2.0 (MPL 2.0)\n\nCopyright (c) Example\n' > "$d/src/upstream/example/LICENSE"
run_in "$d"
expect_code "bundle under MPL-2.0 exits 1" 1 "$code"
expect_line "bundle under MPL-2.0 is reported" "$(printf 'license\twrapped\t%s\tMPL-2.0' "$UPSTREAM_COMMIT")"

# Case 3: a bundle whose license line is not recognized is reported as UNKNOWN.
d="$WORK/bundle-unknown"
make_fixture "$d"
printf 'GNU General Public License v3\n\nCopyright (c) Example\n' > "$d/src/upstream/example/LICENSE"
run_in "$d"
expect_code "unrecognized bundle license exits 1" 1 "$code"
expect_line "unrecognized bundle license is reported as UNKNOWN" "$(printf 'license\twrapped\t%s\tUNKNOWN' "$UPSTREAM_COMMIT")"

# Case 4: build tools have no license gate. A pin under GPL-3.0 does not fail, because build tools are not shipped.
d="$WORK/tool-gpl"
make_fixture "$d"
printf 'gplpkg==1.0 \\\n    --hash=sha256:ffff\n' >> "$d/tools/apm/requirements.txt"
run_in "$d"
expect_code "a GPL build tool does not fail the license check" 0 "$code"
expect_json "a GPL build tool is not listed in the SBOM" "$d" '.components | map(.name) | index("gplpkg") == null'

# Case 5: a known vulnerability in a tool pin fails the gate, and a baseline entry with a reason accepts it.
d="$WORK/vuln"
make_fixture "$d"
export STUB_AUDIT_JSON='{"dependencies":[{"name":"alpha","version":"1.0.0","vulns":[{"id":"PYSEC-1"}]}]}'
run_in "$d"
expect_code "vulnerability exits 1" 1 "$code"
expect_line "vulnerability is reported" "$(printf 'vulnerability\talpha\t1.0.0\tPYSEC-1')"
printf '{"accepted":[{"kind":"vulnerability","package":"alpha","version":"1.0.0","id":"PYSEC-1","reason":"Test accepts it."}]}\n' \
  > "$d/.sbom-baseline.json"
run_in "$d"
expect_code "accepted vulnerability exits 0" 0 "$code"
export STUB_AUDIT_JSON='{"dependencies":[]}'

# Case 6: a bundle license outside the ship list is accepted by a baseline entry with a reason.
d="$WORK/license-accepted"
make_fixture "$d"
printf 'Mozilla Public License 2.0 (MPL 2.0)\n\nCopyright (c) Example\n' > "$d/src/upstream/example/LICENSE"
printf '{"accepted":[{"kind":"license","package":"wrapped","version":"%s","license":"MPL-2.0","reason":"Test accepts it."}]}\n' \
  "$UPSTREAM_COMMIT" > "$d/.sbom-baseline.json"
run_in "$d"
expect_code "accepted bundle license exits 0" 0 "$code"

# Case 7: a baseline entry without a reason is an error.
d="$WORK/no-reason"
make_fixture "$d"
printf '{"accepted":[{"kind":"vulnerability","package":"alpha","version":"1.0.0","id":"PYSEC-1"}]}\n' > "$d/.sbom-baseline.json"
run_in "$d"
expect_code "entry without a reason exits 1" 1 "$code"

# Case 8: an output that fails its schema fails the gate.
d="$WORK/schema"
make_fixture "$d"
code=0
out=$(cd "$d" && STUB_SCHEMA_FAIL=1 sh scripts/build-sbom.sh 2>&1) || code=$?
expect_code "schema failure exits 1" 1 "$code"
expect_line "schema failure is reported" "$(printf 'schema\talf.cdx.json\t-\tfails its schema')"

# Case 9: a pip-audit error is a generation error, not a clean result.
d="$WORK/audit-error"
make_fixture "$d"
code=0
out=$(cd "$d" && STUB_AUDIT_FAIL=1 sh scripts/build-sbom.sh 2>&1) || code=$?
expect_code "pip-audit error exits 1" 1 "$code"
case "$out" in
  *"pip-audit failed"*) ;;
  *) fail "pip-audit error is reported" "$out" ;;
esac

# Case 10: an SPDX schema that does not match its pinned SHA-256 is a generation error.
d="$WORK/bad-schema-hash"
make_fixture "$d"
code=0
out=$(cd "$d" && SBOM_SPDX_SCHEMA_SHA256=0000 sh scripts/build-sbom.sh 2>&1) || code=$?
expect_code "schema hash mismatch exits 1" 1 "$code"
case "$out" in
  *"does not match"*) ;;
  *) fail "schema hash mismatch is reported" "$out" ;;
esac

if [ "$failures" -gt 0 ]; then
  echo "test-build-sbom: $failures failure(s)" >&2
  exit 1
fi
echo "test-build-sbom: passed"
