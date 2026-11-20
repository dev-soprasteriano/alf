# Software bill of materials

The `sbom` job checks the SBOM of ALF's shipped bundles on every pull request, and writes no files. The SBOM workflow (`.github/workflows/sbom.yml`) generates the SBOM on each push to `main`. Run `task sbom` to generate it locally, or `task ci:sbom` to check it the way the pull request does. `task ci` includes the check.

## Outputs

| File | Contents |
| --- | --- |
| `sbom/alf.cdx.json` | CycloneDX 1.6 JSON |
| `sbom/components.tsv` | The rows both SBOM files are built from |
| `sbom/findings.tsv` | Every finding. The job fails when there is one. |

The SBOM workflow uploads `sbom/` as the workflow artifact `sbom-<commit>` on each push to `main`. The pull request check uploads nothing.

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
