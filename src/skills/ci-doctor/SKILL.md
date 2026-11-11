---
name: ci-doctor
description: Check a repository's CI setup against alf's advice, show each gap with its reason, and apply the changes you pick.
disable-model-invocation: true
license: MIT
compatibility: Claude Code, GitHub Copilot CLI
---

# CI doctor

Check the repository's CI setup against the advice below. Report each gap with its reason and its impact, and apply the rows the user picks. Run it from a clone of the repository, as often as you like: each run reads the current state first.

The skill runs with the access of the person who runs it. It does not check access up front. A step that fails for lack of access stops the run and reports the error.

## Steps

1. **Find the repository.** Read the hosting platform, the repository and the default branch from the git remote. If the clone has more than one remote, ask which repository to check.
   - Done when the platform, repository and default branch are known.

2. **Read the current state.** Read:
   - the CI config files on the default branch, from the clone;
   - the stack, as the agent reads it from the repository's files: languages, package managers, and build, test and lint commands;
   - the local command and the pre-commit hook, if the repository has them;
   - the checks that ran on each of the last 10 pull requests, open or closed, opened since the CI config last changed, with their run times, from the platform's CLI;
   - a check reports on a pull request when it finishes with a result on that pull request's head commit. A skipped check, and a check from a workflow no longer on the default branch, does not report;
   - every run on push to the default branch, and whether it repeats a pull request run on the same content;
   - the platform's settings for secret detection, push protection and dependency vulnerability alerts. A capability counts wherever it runs: a platform feature and a CI job both meet the advice.
   - Done when every advice item has a current value, or `unknown` with the reason. A read that fails is `unknown`, with the error.

3. **Find the impact.** For every item whose current value differs from the advice, name what the change affects: a check that becomes required, a job that stops running, a change in run time, or a release step.
   - Done when every differing item names its impact, or says `none found`.

4. **Report.** Show one table: row, item, status, current value, suggested value, why, and impact. Give each advice item one row, numbered as in the advice. When an item has more than one change, give each its own row: 2a, 2b. Use one status per row:
   - `ok`: it already matches the advice.
   - `change`: it differs, and the repository can meet the advice.
   - `later`: the repository can't meet the advice yet. Say what has to be true first, and suggest nothing.
   - `n/a`: the item doesn't apply to this stack or repository.
   - `not available`: the platform has no such feature.
   - `unknown`: the value couldn't be read. Give the reason.
   - `ignored`: the user chose to ignore this row in step 5. Nothing changes.

   Below the table, list the warnings, including: no CI at all, a change that stops a job that other checks depend on, a required check that does not run on some pull requests, such as one behind a path filter, because GitHub then waits for it and blocks those pull requests; and a gap that only a code change can close.
   - Done when every advice item has a row.

5. **Ask.** Ask which `change` rows to apply, and which to ignore. The user answers with row numbers to apply, `all` or `none`, and may name rows to ignore. Mark the ignored rows `ignored`. On `none`, stop.

6. **Apply.** Apply the picked rows on a new branch from the default branch. Change only the lines the picked rows cover, and keep the rest of each file as it is. Then offer to commit the changes and open a pull request.
   - Stop at the first failure. Report what was applied, what failed, and the error text. A failure for lack of access counts as a failure.
   - Done when every picked row is applied, or the run has stopped at a failure.

7. **Verify.** Re-read each changed file. Check that it is valid for its platform. Run the local command once, if the agent can, and report the result. Report a second table: row, file, result (`verified` or `mismatch`), and the error if there is one. Tell the user to watch the first pull request: every check should report, and the pipeline should run on the push.
   - If the user agreed to a pull request, open it after this step. Its body is this report: the applied rows, each changed file, and the verify results, in the same tables the user sees.
   - Done when every applied row has a result.

## Advice

Use the platform's own names for checks and config files.

### Pipeline

1. **Runs on every PR push.** The pipeline runs on each push to a pull request. A run on push to the default branch repeats the pull request run on the same content. The report shows that as a row, with removing the trigger as the suggested value. The person decides: remove the trigger, or ignore the row. Why: every change is checked once, before it merges, and a second run adds time without adding a check.
2. **One check per stage.** Each stage is its own named check, such as build, test, lint, or a scan. Stages run in parallel where the platform allows. Why: a failing check names its cause, and parallel stages finish sooner.
3. **Required checks run on every PR.** A check the team requires runs on every PR push, with no path or branch filter. Other checks may use filters when the team chooses. Why: GitHub waits for a required check that doesn't run, which blocks the pull request.
4. **Scans.** The repository detects secrets and known dependency vulnerabilities. The platform or CI can provide each one. A platform feature counts when it is on, and the report names where it runs. Where neither provides a capability, add a CI scan for it. The agent picks tools that suit the project's ecosystem and are open source, popular, and modern. Why: the advice asks for the capability, not for where it runs.
5. **Repo-doctor's CI advice.** The pipeline follows repo-doctor items 10, 11 and 13: a read-only token, automated updates, and pinned components. Why: the pipeline gets the same protection as the repository's settings.

Required checks are not set by this skill. The report lists the check names, and repo-doctor item 5 makes them required.

### Local loop

6. **Local loop.** One command runs the checks CI runs, on the developer's machine. Use the project's task runner if it has one, such as `task ci` or `make ci`. Add a git pre-commit hook that runs it, where it's fast enough. Why: failures reach the human and the AI in seconds, not after a push and a CI queue. If the full set is too slow for that, the local command runs the fastest subset that still catches most breakage. Examples: unit tests without integration tests, scans of changed files only, or fewer scanners. CI keeps the full set. The report names what the subset skips.
