# Vendored schemas

`scripts/build-sbom.sh` checks each SBOM against the files in `schemas/`. The files are unchanged copies from the sources below. Do not edit them. To update one, download the new version from its source, and update its checksum here.

| File | Source | SHA-256 |
| --- | --- | --- |
| `schemas/bom-1.6.schema.json` | https://cyclonedx.org/schema/bom-1.6.schema.json | `1ebcb88a2c845ecb6ff7bee7aeabdff9422cb0347f3d6875b241bd444b7e098f` |
| `schemas/spdx.schema.json` | https://cyclonedx.org/schema/spdx.schema.json (the CycloneDX schema references it) | `33863a360fc4d348e183d89c1ca7aa0877f481e7eb55be2d4102a30386188a10` |
| `schemas/jsf-0.82.schema.json` | https://cyclonedx.org/schema/jsf-0.82.schema.json (the CycloneDX schema references it) | `2faf5eb3651f2ae5f46091a131770d8d847bbd121139d19c85fc7051bfa58c46` |

The CycloneDX files come from the CycloneDX specification repository, which is Apache-2.0. Its license text is in `schemas/LICENSE-APACHE-2.0`.
