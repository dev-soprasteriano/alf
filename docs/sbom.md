# Software bill of materials

The `sbom` job in CI generates the SBOM of ALF's shipped bundles and checks it. It runs on every pull request. Run `task sbom` to do the same locally. `task ci` includes it.

## Outputs

| File | Contents |
| --- | --- |
| `sbom/alf.cdx.json` | CycloneDX 1.6 JSON |
| `sbom/alf.spdx.json` | SPDX 3.0.1 JSON |
| `sbom/components.tsv` | The rows both SBOM files are built from |
| `sbom/findings.tsv` | Every finding. The job fails when there is one. |

CI uploads `sbom/` as the workflow artifact `sbom`, including when the check fails.

## What is listed

- **Bundles:** each folder in `dist/skills/`. A wrapper's version is the upstream commit in `src/upstream/*/PIN.md`. An in-house skill's version is the commit being built. A bundle's license comes from its upstream `LICENSE`, or from the repository `LICENSE` for an in-house skill.
- **Build tools are not listed.** They do not ship.

## What blocks

| Finding | Blocks the PR |
| --- | --- |
| The generator fails | Yes |
| An output fails its schema | Yes |
| A bundle license is not on `SHIP_ALLOWED`, or is not recognized (`UNKNOWN`) | Yes |

`SHIP_ALLOWED` is set in `scripts/build-sbom.sh`, and it allows MIT only. Add a license there, with review, when a skill needs it. An expression such as `MIT OR Apache-2.0` passes only when every license in it is on the list.

Licenses and schemas are decided in code. No finding can be accepted.

## Limits

- The SBOM covers pull requests only. Pushes to `main` produce no SBOM.
- The job does not check for known vulnerabilities. Dependabot alerts on the build tools' pins.
- Build tools are not in the SBOM.
- The CycloneDX schemas are vendored. The SPDX schema is fetched from spdx.org at check time and must match `SPDX_SCHEMA_SHA256` in `scripts/build-sbom.sh`. Sources are listed in `tools/check-jsonschema/SOURCES.md`.
- A bundle's license is read from the first line of its `LICENSE` file. Only the names that `map_license` lists are recognized.
