# Builds the CycloneDX 1.6 BOM from sbom/components.tsv. Run by scripts/build-sbom.sh with
#   jq -R -s -f scripts/sbom-cyclonedx.jq --arg commit <sha> --arg root_license <id> sbom/components.tsv
# Each row has four tab-separated columns: name, version, license, source.

def rows: split("\n") | map(select(length > 0) | split("\t"));

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
        "licenses": licenses($root_license)
      }
    },
    "components": [
      $rows[]
      | . as [$name, $version, $license, $source]
      | {
          "type": "file",
          "bom-ref": ("bundle:" + $name),
          "name": $name,
          "version": $version,
          "scope": "required",
          "licenses": licenses($license)
        }
        + (if $source == "" then {} else {"externalReferences": [{"type": "vcs", "url": $source}]} end)
    ]
  }
