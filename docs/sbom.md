# Software bill of materials

The `sbom` job in CI generates the SBOM of ALF's shipped bundles and checks it. It runs on every pull request. Run `task sbom` to do the same locally. `task ci` includes it.

## Outputs

| File | Contents |
| --- | --- |
| `sbom/alf.cdx.json` | CycloneDX 1.6 JSON |
| `sbom/alf.spdx.json` | SPDX 3.0.1 JSON |
| `sbom/components.tsv` | The rows both SBOM files are built from |
| `sbom/audit/<tool>.json` | The pip-audit report for each `tools/<tool>/requirements.txt` |
| `sbom/findings.tsv` | Every finding, accepted or not |

CI uploads `sbom/` as the workflow artifact `sbom`, including when the check fails.

## What is listed

- **Bundles:** each folder in `dist/skills/`. A wrapper's version is the upstream commit in `src/upstream/*/PIN.md`. An in-house skill's version is the commit being built. A bundle's license comes from its upstream `LICENSE`, or from the repository `LICENSE` for an in-house skill.
- **Build tools are not listed.** They do not ship. Their pins in `tools/*/requirements.txt` are checked by pip-audit instead.

## What blocks

| Finding | Blocks the PR |
| --- | --- |
| The generator fails, or pip-audit fails | Yes |
| An output fails its schema | Yes. It cannot be accepted. |
| A bundle license is not on `SHIP_ALLOWED`, or is not recognized (`UNKNOWN`) | Yes. Licenses cannot be accepted in the baseline. |
| A known vulnerability in a build tool's pin | Yes, unless accepted |

`SHIP_ALLOWED` is set in `scripts/build-sbom.sh`, and it allows MIT only. Add a license there, with review, when a skill needs it. An expression such as `MIT OR Apache-2.0` passes only when every license in it is on the list.

Bundles get no vulnerability check. A Markdown skill has no package version to match against an advisory.

Build tools get no license check. They are not shipped, so their licenses do not reach ALF's users.

## Fix a finding

| Finding | Fix |
| --- | --- |
| A vulnerability in a build tool's pin | Raise the pin in `tools/<tool>/requirements.in`, run `task tools:lock TOOL=<tool>`, and commit both lock files. If no fix exists, accept it with a reason. |
| A schema failure | Fix `scripts/sbom-cyclonedx.jq` or `scripts/sbom-spdx.jq`. |

Licenses are not fixed or accepted in the baseline. A bundle's license is allowed or not, as set by `SHIP_ALLOWED` in `scripts/build-sbom.sh`. Change that list in code, with review.

## Accept a finding

Add an entry to `accepted` in `.sbom-baseline.json`. A finding passes only when every field matches:

```json
{
  "accepted": [
    {
      "kind": "vulnerability",
      "package": "example",
      "version": "1.0.0",
      "id": "PYSEC-2026-0001",
      "reason": "Affects the parser only. ALF does not call it."
    }
  ]
}
```

- For a `vulnerability` entry, `package` and `version` are the build tool's pinned package. `id` is the advisory ID that `sbom/findings.tsv` lists.
- Every entry needs a non-empty `reason`. Reviewers check the reason in the pull request.
- A schema finding and a license finding cannot be accepted.

## Limits

- The SBOM covers pull requests only. Pushes to `main` produce no SBOM.
- Build tools are not in the SBOM. Dependabot also alerts on their pins.
- The CycloneDX schemas are vendored. The SPDX schema is fetched from spdx.org at check time and must match `SPDX_SCHEMA_SHA256` in `scripts/build-sbom.sh`. Sources are listed in `tools/check-jsonschema/SOURCES.md`.
- A bundle's license is read from the first line of its `LICENSE` file. Only the names that `map_license` lists are recognized.
