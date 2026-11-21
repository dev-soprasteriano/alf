def rows: split("\n") | map(select(length > 0) | split("\t"));

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
