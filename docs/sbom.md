# Software bill of materials

The `sbom` job in CI generates ALF's software bill of materials (SBOM) and checks it. It runs on every pull request. Run `task sbom` to do the same locally. `task ci` includes it.

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

- **Bundles:** each folder in `dist/skills/`. A wrapper's version is the upstream commit in `src/upstream/*/PIN.md`. An in-house skill's version is the commit being built.
- **Packages:** each package pinned in `tools/*/requirements.txt`. They are build-only. A package pinned by two tools is listed once, with both tools.

## What blocks

| Finding | Blocks the PR |
| --- | --- |
| The generator fails, or pip-audit fails | Yes |
| An output fails its schema | Yes. It cannot be accepted. |
| A license outside the allow list | Yes, unless accepted |
| A license the script does not recognize, shown as `UNKNOWN` | Yes, unless accepted |
| A known vulnerability in a pinned package | Yes, unless accepted |

The allow list is MIT, Apache-2.0, BSD-2-Clause, BSD-3-Clause, ISC, Unlicense and CC0-1.0. It is set by `ALLOWED` in `scripts/build-sbom.sh`. An expression such as `MIT OR Apache-2.0` passes only when every license in it is on the list.

The script reads a package's license in this order: `License-Expression`, then `License`, then a `License ::` classifier. It reads a package from the installed `.tools/<tool>` venv. If the runner does not install the package, it reads the package from PyPI for the pinned version.

Bundles get no vulnerability check. A Markdown skill has no package version to match against an advisory.

## Fix a finding

| Finding | Fix |
| --- | --- |
| A license outside the allow list | Replace the package, or accept it with a reason. |
| `UNKNOWN` | Read the license file in the package. Accept it with a reason that names the license. |
| A vulnerability | Raise the pin in `tools/<tool>/requirements.in`, run `task tools:lock TOOL=<tool>`, and commit both lock files. If no fix exists, accept it with a reason. |
| A schema failure | Fix `scripts/sbom-cyclonedx.jq` or `scripts/sbom-spdx.jq`. |

## Accept a finding

Add an entry to `accepted` in `.sbom-baseline.json`. A finding passes only when every field matches:

```json
{
  "accepted": [
    {
      "kind": "license",
      "package": "example",
      "version": "1.0.0",
      "license": "MPL-2.0",
      "reason": "Used only at build time. Not shipped in dist/."
    },
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

- `license` is the value the finding reports: the expression, or `UNKNOWN`.
- `id` is the advisory ID that `sbom/findings.tsv` lists.
- Every entry needs a non-empty `reason`. Reviewers check the reason in the pull request.
- A schema finding cannot be accepted.

## Limits

- The SBOM covers pull requests only. Pushes to `main` produce no SBOM.
- SPDX 3.0.1 has no build-only relationship. A build-only package says so in its `comment`.
- The vendored schemas and their sources are listed in `tools/check-jsonschema/SOURCES.md`.
