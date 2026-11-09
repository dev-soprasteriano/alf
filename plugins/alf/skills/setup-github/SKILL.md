---
name: setup-github
description: Set up a GitHub repository for trunk-based development. Squash-only merges with the PR title as the commit title, head branches deleted on merge, one approval from someone other than the last pusher, and a pull request required for the default branch. When the repo has CI, also requires the confirmed checks to pass and the branch to be up to date before merge. Use only when the user explicitly asks to set up GitHub.
disable-model-invocation: true
license: MIT
compatibility: Claude Code, GitHub Copilot CLI
---

# Set up GitHub

Run this skill by hand from the repository you want to configure, once per repository. It changes settings on GitHub, not the local clone, so it does not need to run again in other clones. It needs `gh` logged in with admin rights on the repository, and `jq` installed.

The script is `scripts/setup-github.sh` in this skill's folder, the folder that holds this SKILL.md. Run it with the repository as the working directory.

## What it sets

- **Merge settings:** squash merges only. The squash commit title is the PR title and the body is blank. Head branches are deleted after merge. Auto-merge is allowed, and "Always suggest updating pull request branches" is on. Other settings are left as they are.
- **Ruleset `trunk-based`** on the default branch:
  - Changes go through a pull request.
  - One approving review is required, from someone other than the person who pushed the latest commit. GitHub checks the pusher, not the commit author.
  - Squash is the only allowed merge method.
  - There are no bypass actors, so these rules apply to admins too.
- **CI gate, only when CI exists:** every check the user confirms must pass before merge. The branch must be up to date with the default branch first. GitHub enforces "up to date" only when at least one required check exists.

The approval rule needs a second person with write access. The script counts direct collaborators only. It does not count team members.

## Steps

1. **Find the CI checks.** Run `scripts/setup-github.sh --discover-checks`. It lists the check names reported on the default branch.
   - If it lists names, show all of them to the user. Ask which ones go into the CI setup. Every name is selected by default. Pass only the names the user confirms, each with `--check NAME`. Do not add or guess names.
   - If it says no check runs exist, the repository has no CI reporting yet. Continue without `--check`. Tell the user the CI gate and the up-to-date rule are skipped, and that the skill can be run again once a CI job exists.
   - Done when the user has confirmed the list, or there are no checks.

2. **Dry run.** Run `scripts/setup-github.sh --dry-run` with the same `--check` flags. It prints the settings and the ruleset it would apply, and changes nothing. Show the output to the user.
   - If the `Approval:` line starts with `warning:`, tell the user that no other collaborator can approve, and that no pull request can merge until one is added. Keep that warning in view while you wait for the user's decision.
   - Wait for the user to confirm. If they decline, stop.
   - Done when the user has confirmed.

3. **Apply.** Run `scripts/setup-github.sh` with the same `--check` flags. It updates the repository settings, then creates the ruleset, or updates it if one named `trunk-based` already exists. It reads both back and compares them. Running it again is safe.
   - If the script stops after the settings step, say which step failed. The settings may have changed, and the ruleset may not exist. Report the error text and stop. Do not retry blindly.
   - A private repository on a plan without rulesets returns an error from the ruleset step. Report it. The settings step has already run.

4. **Report.** Print the script's verification lines. Say which parts were skipped and why. Remind the user that each required check name must match the check run name exactly. If a name never reports, pull requests wait forever, so check the first PR after setup.
   - Done when the report is written.
