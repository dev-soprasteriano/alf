---
name: ask-alf
description: Ask which skill or flow fits your situation. A router over the skills in this repo.
disable-model-invocation: true
---

Follow the skill in full at `../../upstream/mattpocock/ask-matt/SKILL.md`. Read it first and do what it says, using the reference files beside it.

<!-- Local additions go between the markers. scripts/update-upstream.sh rewrites everything else. -->
<!-- overlay:start -->
## Setup skill name

In this repo the setup skill is `/setup-alf`. Wherever the instructions above name `/setup-matt-pocock-skills`, use `/setup-alf` instead.

## Repository and CI setup

Two more standalone skills, both run by hand in a clone of the repository:

- **No CI pipeline, or one with gaps** → **`/ci-doctor`**. It checks the pipeline against alf's advice (build, test, lint, scans, a run on every pull request), and sets one up where there is none.
- **Merge rules and repository settings** → **`/repo-doctor`**. It checks the hosting platform's settings, such as pull requests only, required checks and secret scanning. Run it after `/ci-doctor`, so the checks it makes required exist.
<!-- overlay:end -->
