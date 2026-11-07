# Agentic Lifecycle Foundation

`alf` is 29 agent skills for software work, packaged so a team installs one reviewed copy. The skills cover the whole loop: set up a repo, plan a feature, build it, fix a bug, review it, and improve how you work with agents. They install into Claude Code and GitHub Copilot through [APM](https://microsoft.github.io/apm/).

Most skills are copies of skills from two community repos. Each copy records the commit it came from, is scanned, and changes only through a pull request that someone approves.

## Who it is for

Use alf when a team wants one set of agent skills that it has reviewed. The instructions your agents follow change only when someone approves the change.

If you want the skills for yourself and do not need review, install them from the source. [mattpocock/skills](https://github.com/mattpocock/skills) has its own installer and updates itself.

## What you get

- **A sound set of skills.** 27 come from [mattpocock/skills](https://github.com/mattpocock/skills) and 1 from [humanlayer/skills](https://github.com/humanlayer/skills). Upstream folders are copied byte for byte. `git-commit` is the only skill written here.
- **Updates that get reviewed.** A weekly job opens a pull request with the upstream changes. A scan runs on it. `main` accepts the change only after the scan passes and someone approves. See [How updates are reviewed](#how-updates-are-reviewed).
- **Pick what you install.** Install all 29 skills, or only the ones you need. A skill also installs the skills it calls by name.
- **Local changes survive updates.** Your instructions go in an overlay on a wrapper skill, not in the upstream copy.

## Start here

- New repo? Run `/setup-alf` once. It sets the issue tracker, the triage labels, and the docs layout, and it writes the workflow into `AGENTS.md`.
- Not sure which skill fits? Run `/ask-alf`. It routes you to the right flow.
- Have an idea? Run `/grill-with-docs`. It interviews you and writes the glossary and decision records as terms and decisions get settled.
- The main flow, from idea to ship: `/grill-with-docs`, `/to-spec`, `/to-tickets`, `/implement`, `/code-review`, `/pr`. Then run `/retro` to suggest improvements to the agent's environment.

## Skills

| Need | Skills |
| --- | --- |
| Set up a repo | `setup-alf`, `wizard` for steps only a person can do |
| Plan | `grill-with-docs`, `grill-me`, `grilling`, `to-spec`, `to-tickets`, `wayfinder` |
| Build | `implement`, `implement-spec`, `tdd`, `prototype` |
| Fix a bug | `diagnosing-bugs`, `tdd` |
| Review and ship | `code-review`, `pr`, `git-commit`, `triage` |
| Improve the architecture | `improve-codebase-architecture`, `codebase-design`, `domain-modeling` |
| Research and learn | `research`, `teach`, `show-me` |
| Improve how you work with agents | `retro`, `writing-for-agents` |
| Find your way | `ask-alf` |
| Other | `handoff`, `to-questionnaire`, `wait-what` |

The full list is in `src/skills/`.

## How updates are reviewed

1. **Each copy records its commit.** `src/upstream/<upstream>/PIN.md` lists the commit each skill came from. Nothing is pinned by default, so each weekly update moves the copies to the latest upstream commit.
2. **A weekly job opens the update.** Every Monday at 06:00 UTC, `.github/workflows/update-upstream.yml` runs `task update-upstream`. It copies the changed skills, rebuilds `dist/`, and pushes `upstream/weekly-update`. It opens a pull request, or updates the open one.
3. **The pull request shows what changed.** It lists the skills that moved, the upstream commits between the old and new commit, compare links, new upstream skills that were not copied, and any LICENSE change.
4. **The scan runs on it.** After each push, `scripts/update-upstream.sh` starts the SkillSpector scan on the branch. The scan runs `task ci`. It checks that `dist/` matches a fresh build, then scans every skill. It fails on any MEDIUM, HIGH, or CRITICAL finding.
5. **A person approves it.** A branch rule on `main` requires the `scan` check to pass and one approving review. The approval must come after the last push.
6. **Accepted findings have reasons.** To accept a finding, add it to `.skillspector-baseline.yaml` with a written reason. The scanner catches known risky patterns. It does not replace the reviewer.
7. **Hold a skill when you need to.** `task update-upstream SKILL=<name> REF=<sha or tag>` pins one skill, and the weekly job skips it. `task update-upstream SKILL=<name>` moves it back to latest.

The branch rule is set in GitHub's repository settings, not in this repo. Check it again if you fork or recreate the repo.

## Install

Install [APM](https://microsoft.github.io/apm/) first: `brew install apm`.

The bundles support Claude Code and GitHub Copilot. APM writes each skill into a folder for each target, such as `.claude/skills/` and `.agents/skills/`.

**One user**

Copy the manifest that lists every skill, then install:

```
mkdir -p ~/.apm
curl -fsSL -o ~/.apm/apm.yml https://raw.githubusercontent.com/olillevik/alf/main/dist/user-apm.yml
apm install -g
```

The manifest follows the default branch, so `apm update -g` moves the skills to its newest commit. To pin, add `#<commit sha>` to each line. To drop a skill, delete its line from `~/.apm/apm.yml` and run `apm install -g` again.

**A team**

List the targets and the skills in the team's `apm.yml`. APM stops with "No harness detected" when `targets` is missing.

```yaml
targets:
  - claude
  - copilot
dependencies:
  apm:
    - olillevik/alf/dist/skills/grill-with-docs
```

A skill also installs the skills it calls by name. Its `apm.yml` lists them. For `grill-with-docs` those are `grilling` and `domain-modeling`. Their source depends on how the team lists them:

- **Pin.** Add `#<commit sha>` to each entry, the skill and the skills it calls. All of them then come from that commit:

  ```yaml
  dependencies:
    apm:
      - olillevik/alf/dist/skills/grill-with-docs#<commit sha>
      - olillevik/alf/dist/skills/grilling#<commit sha>
      - olillevik/alf/dist/skills/domain-modeling#<commit sha>
  ```

- **Float.** Leave out the commit. The skills come from the default branch, and `apm update` moves them to its newest commit.

If a team pins a skill but not the skills it calls, those skills still come from the default branch.

## Turn off skills

Delete the skill's line from your `apm.yml`, then run `apm install -g`.

## Extend an upstream skill

A wrapper is a skill that points at one upstream skill. To extend it, add your instructions between the `overlay:start` and `overlay:end` markers in the wrapper's `SKILL.md`. The update script keeps the overlay when it updates the upstream copy.

For example, the overlay in `src/skills/ask-alf/SKILL.md` points `/setup-matt-pocock-skills` at `/setup-alf`.

## Add a skill

- **In-house skill:** create `src/skills/<name>/SKILL.md` with `name` and `description` in its frontmatter. No upstream is needed. If the skill calls other skills by name, list them in `src/skill-dependencies.txt`.
- **Upstream skill:** run `scripts/update-upstream.sh add <upstream> <url> <path>[=wrapper]`. The upstream repo must have a LICENSE on its default branch. The script copies the skill at its latest commit and writes the wrapper. Run `task build-apm`, review the result with `git status`, then commit it.

## Development

- Install [go-task](https://taskfile.dev) (`brew install go-task`), [uv](https://docs.astral.sh/uv/) (`brew install uv`), and [jq](https://jqlang.github.io/jq/) (`brew install jq`).
- Run `task hooks:install` once per clone. After that, `git commit` runs `task ci:staged` first. It checks `dist/`, runs the scope tests, and scans the skill folders of the staged files. It stops the commit if a check fails. CI runs the full `task ci` on every pull request and on each push to `main`.
- `scripts/test-changed-skills.sh` tests `scripts/changed-skills.sh`. `task ci` and `task ci:staged` run it.
- Run `task update-upstream DRY_RUN=1` to print the plan for an update without changing files.
- Run `task build-apm` after changing `src/skills/` or `src/upstream/`, and commit `dist/` with the change. `task ci` fails when `dist/` is out of date.
- `src/skill-dependencies.txt` lists the skills each skill calls by name, and the names it only mentions. The build fails when a skill names another skill that the file does not list.
- If the scan fails, see [docs/skillspector.md](docs/skillspector.md) for how to fix or accept each finding.
- `AGENTS.md` holds the rules agents follow when they change this repo.

## License

MIT. See [LICENSE](LICENSE). Each upstream folder keeps its own LICENSE.
