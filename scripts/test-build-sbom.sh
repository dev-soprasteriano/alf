#!/bin/sh
# Tests scripts/build-sbom.sh in fixture git repos. The fixtures have a stub check-jsonschema tool and a file:// copy of
# the SPDX schema. No network. Run from any directory: sh scripts/test-build-sbom.sh
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
chmod +x "$STUB_CHECK"

fail() {  # name, detail
  echo "FAIL $1"
  printf '  %s\n' "$2"
  failures=$((failures + 1))
}

# Builds a fixture repo in $1 with one wrapped upstream bundle and one in-house bundle. Test cases edit the fixture
# afterwards.
make_fixture() {  # dir
  dir="$1"
  mkdir -p "$dir/scripts" "$dir/src/upstream/example" "$dir/dist/skills/wrapped" "$dir/dist/skills/inhouse"
  cp "$HERE/build-sbom.sh" "$HERE/sbom-cyclonedx.jq" "$HERE/sbom-spdx.jq" "$dir/scripts/"
  mkdir -p "$dir/.tools/check-jsonschema/bin"
  cp "$STUB_CHECK" "$dir/.tools/check-jsonschema/bin/check-jsonschema"

  printf 'Upstream: https://github.com/example/skills\n\n| Skill | Upstream path | Commit | Pinned | Wrapper |\n| --- | --- | --- | --- | --- |\n| wrapped | skills/wrapped | %s | no | wrapped |\n' \
    "$UPSTREAM_COMMIT" > "$dir/src/upstream/example/PIN.md"
  printf 'MIT License\n\nCopyright (c) Example\n' > "$dir/src/upstream/example/LICENSE"
  printf 'MIT License\n\nCopyright (c) ALF\n' > "$dir/LICENSE"
  printf '# wrapped\n' > "$dir/dist/skills/wrapped/SKILL.md"
  printf '# inhouse\n' > "$dir/dist/skills/inhouse/SKILL.md"

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

# Case 1: both bundles pass. Both files list only the two bundles.
d="$WORK/happy"
make_fixture "$d"
head_sha=$(git -C "$d" rev-parse HEAD)
unset STUB_SCHEMA_FAIL
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

# Case 2: a bundle under MPL-2.0 fails, because SHIP_ALLOWED does not allow it.
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

# Case 4: an output that fails its schema fails the gate.
d="$WORK/schema"
make_fixture "$d"
code=0
out=$(cd "$d" && STUB_SCHEMA_FAIL=1 sh scripts/build-sbom.sh 2>&1) || code=$?
expect_code "schema failure exits 1" 1 "$code"
expect_line "schema failure is reported" "$(printf 'schema\talf.cdx.json\t-\tfails its schema')"

# Case 5: an SPDX schema that does not match its pinned SHA-256 is a generation error.
d="$WORK/bad-schema-hash"
make_fixture "$d"
code=0
out=$(cd "$d" && SBOM_SPDX_SCHEMA_SHA256=0000 sh scripts/build-sbom.sh 2>&1) || code=$?
expect_code "schema hash mismatch exits 1" 1 "$code"
case "$out" in
  *"does not match"*) ;;
  *) fail "schema hash mismatch is reported" "$out" ;;
esac

# Case 11: check mode passes and writes nothing to sbom/.
d="$WORK/check-happy"
make_fixture "$d"
code=0
out=$(cd "$d" && sh scripts/build-sbom.sh --check 2>&1) || code=$?
expect_code "check mode passes" 0 "$code"
if [ -e "$d/sbom" ]; then
  fail "check mode writes no files" "sbom/ exists"
fi

# Case 12: check mode fails on a denied bundle license, and still writes nothing.
d="$WORK/check-mpl"
make_fixture "$d"
printf 'Mozilla Public License 2.0 (MPL 2.0)\n\nCopyright (c) Example\n' > "$d/src/upstream/example/LICENSE"
code=0
out=$(cd "$d" && sh scripts/build-sbom.sh --check 2>&1) || code=$?
expect_code "check mode fails on a denied license" 1 "$code"
expect_line "check mode reports the denied license" "$(printf 'license\twrapped\t%s\tMPL-2.0' "$UPSTREAM_COMMIT")"
if [ -e "$d/sbom" ]; then
  fail "check mode writes no files on failure" "sbom/ exists"
fi

if [ "$failures" -gt 0 ]; then
  echo "test-build-sbom: $failures failure(s)" >&2
  exit 1
fi
echo "test-build-sbom: passed"
