---
name: repo-doctor
description: Check a repository's hosting settings against alf's advice, show each gap with its reason, and apply the changes you pick.
disable-model-invocation: true
license: MIT
compatibility: Claude Code, GitHub Copilot CLI
---

# Repo doctor

Check the repository's settings on its hosting platform against the advice below. Report each gap with its reason and its impact, and apply the rows the user picks. Run it from a clone of the repository, as often as you like: each run reads the live state first.

The checks need the platform's CLI, logged in. Applying settings needs admin rights on the repository.

## Steps

1. **Find the repository.** Read the hosting platform and the repository from the git remote. If the clone has more than one remote, ask which repository to check. Find the default branch and the user's access level.
   - Done when the platform, repository, default branch and access level are known. Without admin rights, run steps 2 to 4 and stop after the report.

2. **Read the live state.** For every advice item, read the current value from the platform, from every source that can set it:
   - repository settings, and policy set above the repository, such as the organisation, group or enterprise. When policy above the repository can't be read, say so once in the report, and use the repository's value;
   - every branch rule that applies to the default branch, in every rule mechanism the platform has;
   - the CI config and the dependency update config, as they are on the default branch;
   - every check result, of every kind the platform records, on the head commit of each pull request merged since the CI config last changed, up to the last 10;
   - automation that pushes to the default branch, or opens or approves pull requests, and the token each one uses;
   - everyone who can push to the repository, other than the user, admins and team members included.
   - Done when every advice item has a current value, or `unknown` with the reason.

3. **Find the impact.** For every item whose current value differs from the advice, find what the change would stop: a CI job, a bot, an integration, a release step, a person's way of working. Note any setting the platform's plan doesn't offer. A change that would stop a workflow from pushing, opening, approving or merging a pull request is `later`, not `change`: say what has to be true first.
   - Done when every differing item names its impact, or says `none found`.

4. **Report.** Show one table: row, setting, status, current value, suggested value, why, and impact. Give each advice item one row, numbered as in the advice. When an item has more than one setting to change, give each its own row: 2a, 2b. Use one status per row:
   - `ok`: it already matches the advice.
   - `change`: it differs, the repository can meet the advice, and no workflow in the repository breaks.
   - `later`: the repository can't meet the advice yet. Say what has to be true first, and suggest nothing.
   - `n/a`: the item doesn't apply, such as a cooldown with no update tool.
   - `not available`: the platform or its plan has no such setting.
   - `set by <level>`: policy above the repository enforces it.
   - `unknown`: the value couldn't be read. Give the reason.

   A `change` row is a setting or a config file. Below the table, list the warnings, including: no CI at all, a change that breaks automation, a check that reports on only some pull requests, and a gap that only a code change can close.
   - Done when every advice item has a row.

5. **Ask.** Ask which `change` rows to apply. The user answers with row numbers, `all` or `none`. On `none`, stop.

6. **Apply.** Apply the picked rows. Rows that edit the same rule go in one change.
   - Edit the existing branch rule for the default branch when there is one. When there is none, create one in the platform's newest rule mechanism. Change only the fields the picked rows cover. Keep every other field as it is: other checks, bypass entries, unrelated rules.
   - Where the platform holds one setting in two places, such as a repository setting and a branch rule, set both.
   - Make file changes, such as the dependency update config, on a new branch from the default branch. Then offer to commit them and open a pull request.
   - Stop at the first failure. Report what was applied, what failed, and the error text.
   - Done when every picked row is applied, or the run has stopped at a failure.

7. **Verify.** Read every changed setting back from the platform, and compare it with the suggested value. A platform can accept a request and ignore a field, so the read-back is the proof. Report a second table: row, read-back value, and `verified` or `mismatch`. Tell the user to watch the first pull request after the change: every required check reports, and the approval rule holds.
   - Done when every applied row has a read-back result.

## Advice

Use the platform's own names for these settings.

### Branch and merge rules

1. **Pull requests only.** Every change to the default branch goes through a pull request. Direct pushes and force pushes are blocked. Why: every change gets a review and a CI run, and nobody can rewrite the history.
   - Do not suggest `Restrict updates` (the `update` rule). With no bypass, it blocks pull request merges too.
2. **Independent approval.** A pull request needs one approval, and the latest push must be approved by someone other than the person who pushed it. CI bots can't approve. Why: nobody merges code that only they have seen. This fits a repository with more than one contributor. When nobody but the user can push, mark it `later`.
   - Do not suggest turning off the setting that lets Actions create and approve pull requests while a workflow opens pull requests with the workflow token. Mark it `later`, and say that the workflow needs its own token first.
3. **Squash merges only.** Squash is the only merge method. The commit title is the pull request title, and the body is empty. Why: the default branch gets one commit per change, so each change reads and reverts as one unit.
4. **Short-lived branches.** The source branch is deleted on merge. Authors can update a pull request branch from the default branch, and set a pull request to merge itself once it passes. Why: a branch lives only as long as its change.
5. **CI gate.** The checks CI runs on every pull request must pass before merge. Each required check accepts results only from the CI system that runs it. Why: a broken change stays out of the default branch, and nobody can post a passing result by hand.
   - Suggest a check when the CI config runs it on every pull request, with no path or branch filter, and it reported on every pull request read in step 2. List the other checks with how often they reported. Keep every required check that still qualifies.
   - A required check that never reports blocks every pull request.
   - With no CI, mark it `later`: it fits once the repository has CI.
6. **Tested as merged.** A pull request is tested against the current default branch before it merges: the branch must be up to date, or the platform's merge queue runs the checks. Why: what was tested is what merges. When item 5 requires no check, mark it `later`.
7. **No bypass.** The rules apply to everyone, admins and bots included. Why: there is one path to the default branch. Automation that pushes to the default branch conflicts with this rule. Report it, and let the user choose.

### Security

8. **Secret scanning.** The platform scans every push for credentials, such as API keys and tokens, and rejects a push that contains one. Why: a rejected push leaks nothing, and a merged secret has to be revoked, replaced and scrubbed from history.
9. **Vulnerability alerts.** The platform alerts when a dependency has a known vulnerability, and opens a pull request that moves it to the fixed version. Why: the fix arrives as an ordinary reviewed pull request.
10. **Read-only CI token.** The token a CI job gets by default can read the repository and nothing more. A job that needs to write, such as one that opens pull requests, asks for it in its own config. Why: a compromised step can't push code or change settings.

### Dependency updates

11. **Automated update pull requests.** An update tool opens a pull request when a dependency has a new version, for every package ecosystem in the repository, CI components included. Update jobs the repository runs itself count too. Why: dependencies move in small, reviewed steps.
12. **Cooldown.** The update tool proposes a new version only once the release is 7 days old. Security fixes arrive at once. Why: a hijacked release is usually found and pulled within days, so it never reaches a pull request.
13. **Pinned CI components.** CI refers to every component from outside the repository by full commit hash or digest, with the version in a comment, and the update tool moves the pins. Where the platform can reject an unpinned component, that rule is on. Why: a tag can be moved to new code, and a hash cannot.
