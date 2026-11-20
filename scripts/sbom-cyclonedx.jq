# Builds the CycloneDX 1.6 BOM from sbom/components.tsv. Run by scripts/build-sbom.sh with
#   jq -R -s -f scripts/sbom-cyclonedx.jq --arg commit <sha> sbom/components.tsv
# Each row has eight tab-separated columns: kind, name, version, license, scope, source, tools, hashes.

def rows: split("\n") | map(select(length > 0) | split("\t"));
def csv: if . == "" then [] else split(",") end;

# An expression with operators or parentheses goes in "expression". A single id goes in "id".
# UNKNOWN has no SPDX id, so it goes in "name".
def licenses($expr):
  if $expr == "UNKNOWN" then [{"license": {"name": "UNKNOWN"}}]
  elif ($expr | test("[() ]")) then [{"expression": $expr}]
  else [{"license": {"id": $expr}}]
  end;

rows as $rows
| {
    "bomFormat": "CycloneDX",
    "specVersion": "1.6",
    "version": 1,
    "metadata": {
      "component": {
        "type": "application",
        "bom-ref": "alf",
        "name": "alf",
        "version": $commit,
        "licenses": [{"license": {"id": "MIT"}}]
      }
    },
    "components": [
      $rows[]
      | . as [$kind, $name, $version, $license, $scope, $source, $tools, $hashes]
      | if $kind == "bundle" then
          {
            "type": "file",
            "bom-ref": ("bundle:" + $name),
            "name": $name,
            "version": $version,
            "scope": $scope,
            "licenses": licenses($license)
          }
          + (if $source == "" then {} else {"externalReferences": [{"type": "vcs", "url": $source}]} end)
        else
          ("pkg:pypi/" + ($name | ascii_downcase | gsub("_"; "-")) + "@" + $version) as $purl
          | {
              "type": "library",
              "bom-ref": $purl,
              "name": $name,
              "version": $version,
              "purl": $purl,
              "scope": $scope,
              "licenses": licenses($license),
              "hashes": ($hashes | csv | map({"alg": "SHA-256", "content": .})),
              "properties": ($tools | csv | map({"name": "alf:pinned-by", "value": .}))
            }
        end
    ]
  }
