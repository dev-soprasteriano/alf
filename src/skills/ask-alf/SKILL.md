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

Two more skills off the main flow, both run by hand in a clone of the repository:

- **No CI pipeline, or one with gaps** → **`/ci-doctor`**. It checks the pipeline against alf's advice, and sets one up where there is none.
- **Merge rules and repository settings** → **`/repo-doctor`**. It checks the hosting platform's settings, such as required checks and secret scanning. When both apply, run `/ci-doctor` first: `/repo-doctor` can only require checks that already exist.
<!-- overlay:end -->
