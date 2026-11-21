#!/bin/sh
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
failures=0
UPSTREAM_COMMIT=1111111111111111111111111111111111111111

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

fail() {
  echo "FAIL $1"
  printf '  %s\n' "$2"
  failures=$((failures + 1))
}

make_fixture() {
  dir="$1"
  mkdir -p "$dir/scripts" "$dir/src/upstream/example" "$dir/dist/skills/wrapped" "$dir/dist/skills/inhouse"
  cp "$HERE/build-sbom.sh" "$HERE/sbom-cyclonedx.jq" "$dir/scripts/"
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

run_in() {
  code=0
  out=$(cd "$1" && sh scripts/build-sbom.sh 2>&1) || code=$?
}

expect_code() {
  name=$1
  want=$2
  got=$3
  if [ "$want" != "$got" ]; then
    fail "$name" "exit $got, want $want. Output: $out"
  fi
}

expect_line() {
  name=$1
  expected=$2
  if ! printf '%s\n' "$out" | grep -qxF "$expected"; then
    fail "$name" "missing output line: $expected. Output: $out"
  fi
}

expect_json() {
  name=$1
  dir=$2
  expr=$3
  if ! jq -e "$expr" "$dir/sbom/alf.cdx.json" > /dev/null 2>&1; then
    fail "$name" "sbom/alf.cdx.json does not satisfy: $expr"
  fi
}

d="$WORK/happy"
make_fixture "$d"
head_sha=$(git -C "$d" rev-parse HEAD)
unset STUB_SCHEMA_FAIL
run_in "$d"
expect_code "happy path exits 0" 0 "$code"
expect_json "happy: only the two bundles are listed" "$d" '.components | length == 2'
expect_json "happy: wrapped bundle has its upstream commit" "$d" \
  '.components[] | select(.name == "wrapped") | .version == "1111111111111111111111111111111111111111"'
expect_json "happy: in-house bundle has the ALF commit" "$d" \
  ".components[] | select(.name == \"inhouse\") | .version == \"$head_sha\""

d="$WORK/bundle-mpl"
make_fixture "$d"
printf 'Mozilla Public License 2.0 (MPL 2.0)\n\nCopyright (c) Example\n' > "$d/src/upstream/example/LICENSE"
run_in "$d"
expect_code "bundle under MPL-2.0 exits 1" 1 "$code"
expect_line "bundle under MPL-2.0 is reported" "$(printf 'license\twrapped\t%s\tMPL-2.0' "$UPSTREAM_COMMIT")"

d="$WORK/bundle-unknown"
make_fixture "$d"
printf 'GNU General Public License v3\n\nCopyright (c) Example\n' > "$d/src/upstream/example/LICENSE"
run_in "$d"
expect_code "unrecognized bundle license exits 1" 1 "$code"
expect_line "unrecognized bundle license is reported as UNKNOWN" "$(printf 'license\twrapped\t%s\tUNKNOWN' "$UPSTREAM_COMMIT")"

d="$WORK/schema"
make_fixture "$d"
code=0
out=$(cd "$d" && STUB_SCHEMA_FAIL=1 sh scripts/build-sbom.sh 2>&1) || code=$?
expect_code "schema failure exits 1" 1 "$code"
expect_line "schema failure is reported" "$(printf 'schema\talf.cdx.json\t-\tfails its schema')"

d="$WORK/check-happy"
make_fixture "$d"
code=0
out=$(cd "$d" && sh scripts/build-sbom.sh --check 2>&1) || code=$?
expect_code "check mode passes" 0 "$code"
if [ -e "$d/sbom" ]; then
  fail "check mode writes no files" "sbom/ exists"
fi

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
