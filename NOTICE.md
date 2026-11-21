# Third-party notices

alf copies skills from the upstream repositories below. Each upstream is MIT-licensed. Each copy keeps the upstream's license text in `src/upstream/<upstream>/LICENSE` and in every `dist/skills/<skill>/LICENSE`. `src/upstream/<upstream>/PIN.md` records the commit of each copied skill.

## mattpocock/skills

- Source: https://github.com/mattpocock/skills
- License: MIT. Copyright (c) 2026 Matt Pocock. Full text: [src/upstream/mattpocock/LICENSE](src/upstream/mattpocock/LICENSE).
- Skills: `ask-alf` (from `ask-matt`), `code-review`, `codebase-design`, `diagnosing-bugs`, `domain-modeling`, `grill-me`, `grill-with-docs`, `grilling`, `handoff`, `implement`, `implement-spec`, `improve-codebase-architecture`, `pr`, `prototype`, `research`, `retro`, `setup-alf` (from `setup-matt-pocock-skills`), `tdd`, `teach`, `to-questionnaire`, `to-spec`, `to-tickets`, `triage`, `wait-what`, `wayfinder`, `wizard`, `writing-for-agents`.

## humanlayer/skills

- Source: https://github.com/humanlayer/skills
- License: MIT. Copyright (c) 2026 HumanLayer. Full text: [src/upstream/humanlayer/LICENSE](src/upstream/humanlayer/LICENSE).
- Skills: `show-me`.

## Vendored schemas

`tools/check-jsonschema/schemas/` holds the CycloneDX schemas that `scripts/build-sbom.sh` checks the SBOM against. Sources and checksums are in [tools/check-jsonschema/SOURCES.md](tools/check-jsonschema/SOURCES.md).

- **CycloneDX schemas** (`bom-1.6.schema.json`, `spdx.schema.json`, `jsf-0.82.schema.json`). Source: https://cyclonedx.org. License: Apache-2.0. Full text: [LICENSE-APACHE-2.0](tools/check-jsonschema/schemas/LICENSE-APACHE-2.0). The files carry no copyright notice.

## alf

The in-house skills `ci-doctor`, `git-commit` and `repo-doctor`, and all other files except the vendored schemas above, fall under the repository [LICENSE](LICENSE).
