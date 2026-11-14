# Harness equivalents

Claude Code and GitHub Copilot CLI ship their own commands. Some do part of what an alf skill does. This page tells you which one to run for each task.

Checked on 2026-11-14 against the Claude Code docs and Copilot CLI 1.0.112. Both harnesses change weekly, so a command here can be renamed or removed.

## How to read the tables

Each table has one row per alf skill, and one column per harness with the closest built-in. "None" means the harness ships no command, skill or agent for the task. The last column says what to run:

| Use | Meaning | Skills |
| --- | --- | --- |
| `skill` | The harness has nothing for this task. Run the alf skill. | 18 |
| `both` | The built-in does one part and the skill does another. Run each for its part. | 10 |
| `either` | The built-in does most of the job. Run the skill only when you need what it adds. | 3 |

## Software development lifecycle

### Plan

| alf skill | What the skill does | Claude Code | Copilot CLI | Use |
| --- | --- | --- | --- | --- |
| `grill-with-docs`, `grill-me`, `grilling` | Interviews you to stress-test a plan. `grill-with-docs` also writes ADRs and the glossary. | `/plan` (plan mode) | `/plan`, then `/rubber-duck` for a critique | `both`: run `/plan` for work that fits one session. Run the skill for a decision that is costly to reverse. |
| `to-spec` | Writes a spec from the conversation and publishes it to the issue tracker. | None. `/plan` saves its plan on your machine. | None. `/plan` saves its plan on your machine. | `skill` |
| `to-tickets` | Splits a spec into tickets with blocking links, in the tracker. | None | None | `skill` |
| `wayfinder` | Plans work too big for one session as decision tickets in the tracker. | None | None | `skill` |

### Build

| alf skill | What the skill does | Claude Code | Copilot CLI | Use |
| --- | --- | --- | --- | --- |
| `implement`, `implement-spec` | Builds from a ticket or spec: fetches the ticket, calls `tdd`, runs the checks, calls `code-review`, commits. | Auto mode, `/goal`, `/batch` | `/autopilot`, `/fleet`, `/delegate` | `both`: run the skill, in the built-in mode that lets the agent work without stopping. For a small change, the built-in mode alone is enough. |
| `tdd` | Red-green-refactor at agreed seams. Also used to fix a bug. | None | None | `skill` |
| `prototype` | Builds a throwaway prototype to answer a design question. | None | None | `skill` |

### Fix a bug

| alf skill | What the skill does | Claude Code | Copilot CLI | Use |
| --- | --- | --- | --- | --- |
| `diagnosing-bugs` | Builds a tight pass/fail loop for the bug, then tests hypotheses against it. | None. `/debug` diagnoses Claude Code, not your code. | None. `/diagnose` diagnoses Copilot CLI, not your code. | `skill` |

### Review and ship

| alf skill | What the skill does | Claude Code | Copilot CLI | Use |
| --- | --- | --- | --- | --- |
| `code-review` | Checks a diff against the repo's coding standards, a code-smell baseline and the originating spec. | `/code-review` finds bugs. `/security-review` finds vulnerabilities. | `/review` finds bugs. `/security-review` finds vulnerabilities. | `both`: the built-ins find bugs and vulnerabilities. The skill checks standards and spec. |
| `pr` | Gives the PR body a fixed template: summary diagram, before/after evidence, merge danger. | No command. Ask for a PR. `/autofix-pr` fixes CI failures and review comments. | `/pr create` opens the PR. `/pr fix` and `/pr auto` drive it to green. | `both`: the skill writes the body. The built-in opens and drives the PR. |
| `git-commit` | Writes a one-line imperative subject from the diff and commits. | No command. Ask for a commit. | No command. Ask for a commit. | `either`: both harnesses commit when you ask. The skill only sets the message style. See [agent-instructions.md](agent-instructions.md). |
| `triage` | Moves issues and external PRs through triage roles, and writes agent-ready briefs. | None | None | `skill` |

### Design and architecture

| alf skill | What the skill does | Claude Code | Copilot CLI | Use |
| --- | --- | --- | --- | --- |
| `improve-codebase-architecture` | Scans the codebase for shallow modules, shows an HTML report, and grills through the one you pick. | None. `/simplify` cleans up the current diff only. | None. `/rubber-duck` critiques a design you give it. | `skill` |
| `codebase-design` | Gives the agent the deep-module vocabulary. | None | None | `skill` |
| `domain-modeling` | Maintains `GLOSSARY.md` and the ADRs. | None | None | `skill` |

### Research and learn

| alf skill | What the skill does | Claude Code | Copilot CLI | Use |
| --- | --- | --- | --- | --- |
| `research` | Starts a background agent that reads primary sources and saves a cited Markdown file in the repo. | `/deep-research` returns a cited report. | `/research` saves a cited report in the session folder. `/share file research` exports it. | `either`: run the built-in for a quick question. Run the skill when the team needs the findings in the repo, from primary sources only. |
| `teach` | Teaches a topic over several sessions, with a mission, lessons and learning records on disk. | None. The Explanatory and Learning output styles explain as they code. | None. `/ask` answers a side question. | `skill` |
| `show-me` | Explains the current topic with the smallest diagram, tree or sketch that fits. | None. Ask for a diagram. | None. Ask for a diagram. | `both`: a plain request for a diagram works. The skill picks the view for you. |

## Meta skills

### Set up

| alf skill | What the skill does | Claude Code | Copilot CLI | Use |
| --- | --- | --- | --- | --- |
| `setup-alf` | Records the issue tracker, triage labels and domain doc layout for the other skills. | None. `/init` writes `CLAUDE.md`. | None. `/init` writes `.github/copilot-instructions.md`. | `skill`. Run `/init` as well: it describes the codebase, and `setup-alf` does not. |
| `repo-doctor` | Checks the repository's hosting settings against alf's advice and applies the rows you pick. | None. `/doctor` checks the Claude Code installation. | None | `skill` |
| `ci-doctor` | Checks the CI setup against alf's advice and applies the rows you pick. | None | None | `skill` |
| `wizard` | Generates a bash wizard for steps only a person can do. | None | None | `skill` |

### Find your way

| alf skill | What the skill does | Claude Code | Copilot CLI | Use |
| --- | --- | --- | --- | --- |
| `ask-alf` | Names the alf skill or flow that fits your situation. | None. `/skills` lists the installed skills. | None. `/skills list` lists the installed skills. | `skill` |

### Work better with agents

| alf skill | What the skill does | Claude Code | Copilot CLI | Use |
| --- | --- | --- | --- | --- |
| `retro` | Reads a session and proposes changes to the agent's environment: navigation pointers, automated checks, coding standards, tool cost. | `/insights` reports on recent sessions. It proposes no repo changes. | `/chronicle improve` proposes edits to `.github/copilot-instructions.md`. | `either` in Copilot CLI: run `/chronicle improve` to tune the instructions file. Run the skill when the fix is a check, a hook or a standard. `skill` in Claude Code. |
| `writing-for-agents` | Style guide for skills, `AGENTS.md` and `CLAUDE.md`. | None | `/chronicle skills create` drafts a skill. `/refine` rewrites a rough prompt. | `both` in Copilot CLI, `skill` in Claude Code. |
| `wait-what` | Makes the agent re-pitch its last message in Simplified Technical English and glossary terms. | None | None | `skill` |

### Hand over and ask

| alf skill | What the skill does | Claude Code | Copilot CLI | Use |
| --- | --- | --- | --- | --- |
| `handoff` | Writes a short, redacted brief for a fresh agent, with links to existing artefacts and the skills to call. | `/resume`, `/teleport` | `/resume`, `/delegate` | `both`: run the built-in to continue your own session. Run the skill to hand work to another person or another harness. |
| `to-questionnaire` | Writes a questionnaire for another person to fill in. | None | None | `skill` |

## When the built-in is enough

For these skills, the built-in or a plain request does a large part of the job. The table says what you lose when you skip the skill.

| alf skill | Run instead: Claude Code | Run instead: Copilot CLI | You lose |
| --- | --- | --- | --- |
| `git-commit` | Ask for a commit. | Ask for a commit. | The message style. An instruction gives you the same: see [agent-instructions.md](agent-instructions.md). |
| `research` | `/deep-research` | `/research`, then `/share file research` | The primary-sources rule, and a file saved in the repo. |
| `retro` | `/insights`, for a report only | `/chronicle improve` | Proposals for checks, hooks and standards. |
| `show-me` | Ask for a diagram or a call tree. | Ask for a diagram or a call tree. | A consistent choice of the smallest view. |
| `wait-what` | Ask the agent to explain again in plain words. | The same. | The glossary terms and the Simplified Technical English rule. |
| `handoff` | `/resume` | `/resume`, or `/delegate` to the cloud agent | A redacted brief that another person or harness can start from. |
| `grill-me`, `grilling` | `/plan` | `/plan`, then `/rubber-duck` | An agent that challenges the decision, not only the missing details. |
| `implement` | `/plan`, then auto mode | `/plan`, then `/autopilot` | The chain of `tdd`, checks and `code-review` before the commit. |

Do not skip these:

- `code-review`: the built-in review does not check your coding standards or the spec.
- `repo-doctor` and `ci-doctor`: they check branch rules, secret detection and dependency alerts. Neither harness has a built-in for that.

## Same name, different command

Three alf skills share a name with a built-in command. When you type the name, check which one runs: the built-in and the skill do different jobs.

| Name | Harness | Built-in | alf skill |
| --- | --- | --- | --- |
| `/code-review` | Claude Code | Finds bugs in the diff. | Checks the diff against standards and spec. |
| `/pr` | Copilot CLI | Creates, fixes and merges the pull request. | Writes the PR body from a template. |
| `/research` | Copilot CLI | Writes a report to the session folder. | Writes a report to the repo. |

## How this page was checked

Every cell comes from the vendor docs. No built-in was run, so the "Use" column compares descriptions, not outputs. Which command wins in a name clash is not verified.

Sources:

- Claude Code: [commands](https://code.claude.com/docs/en/commands.md), [skills](https://code.claude.com/docs/en/skills.md), [workflows](https://code.claude.com/docs/en/workflows.md), [code review](https://code.claude.com/docs/en/code-review-local.md), [output styles](https://code.claude.com/docs/en/output-styles.md).
- Copilot CLI: [command reference](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference), [chronicle](https://docs.github.com/en/copilot/how-tos/copilot-cli/use-copilot-cli/chronicle), [research](https://docs.github.com/en/copilot/concepts/agents/copilot-cli/research), [code review](https://docs.github.com/en/copilot/how-tos/copilot-cli/use-copilot-cli/agentic-code-review), [changelog](https://github.com/github/copilot-cli/blob/main/changelog.md).

Maintainers: check the page again when a harness release names one of these areas, and at least once a quarter. Update the cells, the date and the version at the top.
