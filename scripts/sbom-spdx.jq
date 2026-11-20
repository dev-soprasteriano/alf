# Builds the SPDX 3.0.1 JSON-LD document from sbom/components.tsv. Run by scripts/build-sbom.sh with
#   jq -R -s -f scripts/sbom-spdx.jq --arg commit <sha> --arg created <iso-time> --arg root_license <id> \
#     sbom/components.tsv
# Each row has eight tab-separated columns: kind, name, version, license, scope, source, tools, hashes.
# SPDX 3.0.1 has no build-only relationship, so a build-only package says so in its comment.

def rows: split("\n") | map(select(length > 0) | split("\t"));
def csv: if . == "" then [] else split(",") end;
def slug: gsub("[^A-Za-z0-9.-]"; "_");

# SPDX refers to "no assertion" by a fixed IRI. It defines no element for it.
def license_id($expr):
  if $expr == "UNKNOWN" then "https://spdx.org/rdf/3.0.1/terms/ExpandedLicensing/NoAssertionLicense"
  else "urn:alf:license:" + ($expr | slug)
  end;

def license_element($expr):
  {
    "type": "simplelicensing_LicenseExpression",
    "spdxId": license_id($expr),
    "creationInfo": "_:creationinfo",
    "simplelicensing_licenseExpression": $expr
  };

def package_element:
  . as [$kind, $name, $version, $license, $scope, $source, $tools, $hashes]
  | if $kind == "bundle" then
      {
        "type": "software_Package",
        "spdxId": ("urn:alf:bundle:" + $name + "@" + $version),
        "creationInfo": "_:creationinfo",
        "name": $name,
        "software_packageVersion": $version,
        "software_primaryPurpose": "file",
        "software_downloadLocation": (if $source == "" then "NOASSERTION" else $source end),
        "comment": "Skill bundle in dist/skills/."
      }
    else
      {
        "type": "software_Package",
        "spdxId": ("urn:alf:package:" + $name + "@" + $version),
        "creationInfo": "_:creationinfo",
        "name": $name,
        "software_packageVersion": $version,
        "software_primaryPurpose": "library",
        "software_downloadLocation": "NOASSERTION",
        "software_packageUrl": ("pkg:pypi/" + ($name | ascii_downcase | gsub("_"; "-")) + "@" + $version),
        "verifiedUsing": ($hashes | csv | map({"type": "Hash", "algorithm": "sha256", "hashValue": .})),
        "comment": ("Build-only. Pinned by " + ($tools | csv | map("tools/" + .) | join(", ")) + ".")
      }
    end;

def license_relationship:
  . as [$kind, $name, $version, $license]
  | ((if $kind == "bundle" then "urn:alf:bundle:" else "urn:alf:package:" end) + $name + "@" + $version) as $from
  | {
      "type": "Relationship",
      "spdxId": ("urn:alf:relationship:license:" + $name + "@" + $version),
      "creationInfo": "_:creationinfo",
      "from": $from,
      "relationshipType": "hasDeclaredLicense",
      "to": [license_id($license)]
    };

rows as $rows
| {"type": "CreationInfo", "@id": "_:creationinfo", "specVersion": "3.0.1", "created": $created, "createdBy": ["urn:alf:tool:build-sbom"]} as $creation
| {"type": "Tool", "spdxId": "urn:alf:tool:build-sbom", "creationInfo": "_:creationinfo", "name": "scripts/build-sbom.sh"} as $tool
| {
    "type": "software_Package",
    "spdxId": ("urn:alf:alf@" + $commit),
    "creationInfo": "_:creationinfo",
    "name": "alf",
    "software_packageVersion": $commit,
    "software_primaryPurpose": "application",
    "software_downloadLocation": "NOASSERTION"
  } as $root
| {
    "type": "Relationship",
    "spdxId": "urn:alf:relationship:root-license",
    "creationInfo": "_:creationinfo",
    "from": $root.spdxId,
    "relationshipType": "hasDeclaredLicense",
    "to": [license_id($root_license)]
  } as $root_rel
| ([$root_license] + ($rows | map(.[3])) | unique | map(select(. != "UNKNOWN")) | map(license_element(.))) as $licenses
| ($rows | map(package_element)) as $packages
| ($rows | map(license_relationship) + [$root_rel]) as $relationships
| ([$root] + $packages + $licenses + $relationships + [$tool]) as $elements
| {
    "@context": "https://spdx.org/rdf/3.0.1/spdx-context.jsonld",
    "@graph": ([
      $creation,
      {
        "type": "SpdxDocument",
        "spdxId": ("urn:alf:document:" + $commit),
        "creationInfo": "_:creationinfo",
        "name": "alf",
        "profileConformance": ["core", "software", "simpleLicensing"],
        "rootElement": [$root.spdxId],
        "element": ($elements | map(.spdxId))
      }
    ] + $elements)
  }
