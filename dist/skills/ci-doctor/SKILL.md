---
name: ci-doctor
description: Check a repository's CI setup against alf's advice, or set one up where there is none. Show each gap with its reason, and apply the changes you pick.
disable-model-invocation: true
license: MIT
compatibility: Claude Code, GitHub Copilot CLI
---

# CI doctor

Check the repository's CI setup against the advice below. Report each gap with its reason and its impact, and apply the rows the user picks. Run it from a clone of the repository, as often as you like: each run reads the current state first. A repository with no CI config follows the same steps, with the rules under [No CI config](#no-ci-config).

The skill runs with the access of the person who runs it. It does not check access up front. A step that fails for lack of access stops the run and reports the error. A read in step 2 that fails is the exception: it records `unknown` and the run goes on.

## Steps

1. **Find the repository.** Read the hosting platform and the repository from the git remote. If the clone has more than one remote, ask which repository to check. Read the default branch from the platform; when that read fails, use `origin/HEAD`, then the current branch, and say which one you used. Name the CI system the repository uses, from its CI config files. The rest of the run uses that CI system's config location, trigger names, check names and CLI.
   - Done when the platform, repository, default branch and CI system are known.

2. **Read the current state.** Read:
   - the CI config files on the default branch, from the clone;
   - the stack, as the agent reads it from the repository's files: languages, package managers, and build, test and lint commands, whether or not CI runs them;
   - the local command and the pre-commit hook, if the repository has them;
   - the checks that ran on each of the last 10 pull requests, open or closed, opened since the CI config last changed, with their run times, from the CLI. A check has a result on a pull request when its run finishes, passed or failed, on that pull request's head commit. A skipped run has no result, and neither does a check from a config no longer on the default branch;
   - the platform's settings for secret detection, push protection and dependency vulnerability alerts. A capability counts wherever it runs: a platform feature and a CI job both meet the advice;
   - the default permission of the CI token, any rule that rejects unpinned CI components, and the checks the default branch already requires.
   - Done when every advice item has a current value, or `unknown` with the reason and the error.

3. **Find the impact.** For every item whose current value differs from the advice, name what the change affects: a check that becomes required, a job that stops running, a change in run time, or a release step.
   - Done when every differing item names its impact, or says `none found`.

4. **Report.** Show one table: row, item, status, current value, suggested value, why, and impact. Give each advice item one row, numbered as in the advice. When an item has more than one change, give each its own row: 2a, 2b. Use one status per row:
   - `ok`: it already matches the advice.
   - `change`: it differs, and the repository can meet the advice.
   - `later`: the repository can't meet the advice yet. Say what has to be true first, and suggest nothing.
   - `n/a`: the item doesn't apply to this stack or repository.
   - `not available`: the platform or CI system has no such feature.
   - `unknown`: the value couldn't be read. Give the reason.
   - `ignored`: the user chose to ignore this row in step 5. Nothing changes.

   Below the table, list the warnings, including: no CI at all, a change that stops a job that other checks depend on, a required check that does not run on some pull requests, such as one behind a path filter, because the merge gate then waits for it and blocks those pull requests; and a gap that only a code change can close.
   - Done when every advice item has a row.

5. **Ask.** Ask which `change` rows to apply, and which to ignore. The user answers with row numbers to apply, `all` or `none`, and may name rows to ignore. Mark the ignored rows `ignored`. On `none`, stop.

6. **Apply.** Apply the picked rows on a new branch from the default branch. Change only the lines the picked rows cover, and keep the rest of each file as it is. Then offer to commit the changes and open a pull request.
   - Stop at the first failure. Report what was applied, what failed, and the error text. A failure for lack of access counts as a failure.
   - Done when every picked row is applied, or the run has stopped at a failure.

7. **Verify.** Re-read each changed file. Check it with the CI system's own validator or linter where the agent can run one; otherwise parse it, and report the result as `parsed only`. Run the local command once, if the agent can, and report the result. Report a second table: row, file, result (`verified`, `parsed only` or `mismatch`), and the error if there is one. Tell the user to watch the first pull request: every check should run on each push to it and finish, passed or failed.
   - If the user agreed to a pull request, open it after this step. Its body is this report: the applied rows, each changed file, and the verify results, in the same tables the user sees.
   - Name the next step: once this pull request has merged, run `/repo-doctor`. Its item 5 makes these checks required before merge, from their results on this pull request.
   - Done when every applied row has a result, and the user has the next step.

## No CI config

When the repository has no CI config:

- **Step 1:** ask the user which CI system to use. Suggest the hosting platform's own, when it has one.
- **Step 2:** the current value of every pipeline item (1 to 5) is `none`.
- **Step 4:** each pipeline item the stack can meet is a `change` row. Its suggested value names the new config file and the checks it adds. When a platform setting for a scan is `unknown`, the scan row is `change`, with a warning that the CI scan may repeat a platform feature.
- **Step 5:** rows 1 and 3, the trigger, go with every other pipeline row the user picks. A config without its trigger never runs.
- **Step 6:** create the config in the CI system's standard location, holding what the picked rows cover.

## Advice

Use the platform's and the CI system's own names for checks, settings and config files.

### Pipeline

1. **Runs on every PR push.** The pipeline runs on each push to a pull request. Why: every change is checked before it merges.
2. **Build, test and lint.** The pipeline builds the project, runs its tests and lints it, each with the command the stack already has, and each as its own named check. Stages run in parallel where the CI system allows. Why: a broken build, a failing test and a lint error each stop the change, a failing check names its cause, and parallel stages finish sooner.
   - A stack with nothing to build, such as an interpreted project with no compile step: mark the build row `n/a`.
   - A repository with no tests, or no linter set up: mark that row `later`, and say what has to exist first. Writing tests and picking a linter are the team's work.
3. **Required checks run on every PR.** A check the team requires runs on every PR push, with no path or branch filter. Other checks may use filters when the team chooses. Why: the merge gate waits for a required check that doesn't run, which blocks the pull request.
4. **Scans.** The repository detects secrets and known dependency vulnerabilities. When it builds container images or holds infrastructure as code, it scans those too. The platform or CI can provide each one. A platform feature counts when it is on, and the report names where it runs. Where neither provides a capability, add a CI scan for it, as its own named check. The agent picks tools that suit the project's ecosystem and are open source, popular, and modern. Why: the advice asks for the capability, not for where it runs.
5. **Repo-doctor's CI advice.** The pipeline follows repo-doctor items 10, 11 and 13: a read-only token, automated updates, and pinned components. Why: the pipeline gets the same protection as the repository's settings.

This skill does not make checks required. Step 7 names the next step.

### Local loop

6. **Local loop.** One command runs the checks CI runs, on the developer's machine. Use the project's task runner if it has one, such as `task ci` or `make ci`. Without one, add a command under a name that doesn't clash with a built-in command of the stack's tools. Add a git pre-commit hook that runs it, where it's fast enough. Keep the hook in a folder the repository tracks, and give the user the one command that turns it on. Why: failures reach the human and the AI in seconds, not after a push and a CI queue. If the full set is too slow for that, or a tool can't run locally, the local command runs the fastest subset that still catches most breakage. Examples: unit tests without integration tests, scans of changed files only, or fewer scanners. CI keeps the full set. The report names what the subset skips.
