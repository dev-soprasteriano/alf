# Agentic Lifecycle Foundation

`alf` is a sound base of agent skills for the basics of a software flow. Install it into Claude Code or GitHub Copilot through [APM](https://microsoft.github.io/apm/), and your team starts from the same skills.

- **Covers the flow.** Setup, planning, building, debugging, review, shipping and architecture each have at least one skill. See [Skills](#skills).
- **Reviewed and scanned.** Each skill records its upstream commit. Every skill is scanned for security risks with [SkillSpector](https://github.com/NVIDIA/skillspector). Changes reach the default branch only through a pull request that passes the scan and gets a human approval.
- **Pinned for the team.** Pin a commit, and every member installs the same skills.
- **Take what you need.** Install every skill with one manifest, or only the ones you need. A skill brings the skills it calls.

Teams get the most from it. A single developer can use the same set with the one-user manifest below.

## Start here

- New repo: run `/setup-alf` once.
- Not sure which skill fits: run `/ask-alf`.
- Idea to ship: `/grill-with-docs`, `/to-spec`, `/to-tickets`, `/implement`, `/code-review`, `/pr`. Then run `/retro`.

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

`dist/user-apm.yml` lists every skill.

## Install

Install APM first: `brew install apm`.

**One user.** Copy the manifest that lists every skill, then install:

```sh
mkdir -p ~/.apm
curl -fsSL -o ~/.apm/apm.yml https://raw.githubusercontent.com/olillevik/alf/main/dist/user-apm.yml
apm install -g
```

**A team.** Add the skills to the team's `apm.yml`. Set `targets`, or APM stops with "No harness detected":

```yaml
targets:
  - claude
  - copilot
dependencies:
  apm:
    - olillevik/alf/dist/skills/grill-with-docs
```

A skill also installs the skills it calls by name. For `grill-with-docs`, those are `grilling` and `domain-modeling`. To pin a set, add `#<commit sha>` to every entry, including the skills it calls. A called skill without a pin comes from the default branch.

**Turn off a skill.** Delete its line from your `apm.yml`, then run `apm install -g`.

## Update

Skills follow the default branch unless you pin them. Run `apm update -g` for one user, or `apm update` for a team, to move to the newest commit. Pin a commit to keep a skill fixed until you change the pin.

## Maintain alf

To add a skill, change one, or change how updates are reviewed, read [docs/maintainers.md](docs/maintainers.md).

## License

MIT. See [LICENSE](LICENSE). Each upstream folder keeps its own LICENSE.
