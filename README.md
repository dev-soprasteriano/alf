# Agentic Lifecycle Foundation

`alf` is a sound base of agent skills for the core of the software development lifecycle. Install it into Claude Code or GitHub Copilot through [APM](https://microsoft.github.io/apm/), and your team starts from the same skills.

- **Built for the full development lifecycle.** Start a project, plan it, build it, fix it, review it and ship it, with skills for each step. See [Skills](#skills).
- **Reviewed and scanned.** Each skill records its upstream commit. Every skill is scanned for security risks. All upstream changes go through a security scan and a human review.
- **You control updates.** Pin a commit, and the team runs the same skills until someone moves the pin.
- **Flexible.** Install every skill from one manifest, or only the skills you need.

## Install

Install APM first: `brew install apm`.

To install every foundation skill, copy the manifest and install it:

```sh
mkdir -p ~/.apm
curl -fsSL -o ~/.apm/apm.yml https://raw.githubusercontent.com/dev-soprasteriano/alf/main/dist/user-apm.yml
apm install -g
```

To install only some skills, or to combine alf with other skills, write your own `apm.yml` and run `apm install`. Commit it to share the set with your team:

```yaml
targets:
  - claude
  - copilot
dependencies:
  apm:
    - dev-soprasteriano/alf/dist/skills/grill-with-docs
```

A skill also installs the skills it calls by name. For `grill-with-docs`, those are `grilling` and `domain-modeling`. To pin a set, add `#<commit sha>` to every entry, including the skills it calls. A called skill without a pin comes from the default branch.

**Turn off a skill.** Delete its line from your `apm.yml`, then run `apm install`. For the global file at `~/.apm/apm.yml`, run `apm install -g`.

## Getting started

- New repo: run `/setup-alf` once.
- Not sure which skill fits: run `/ask-alf`.
- Idea to ship: `/grill-with-docs`, `/to-spec`, `/to-tickets`, `/implement`, `/code-review`, `/pr`. Then run `/retro`.

## Skills

| Need | Skills |
| --- | --- |
| Set up a repo | `setup-alf`, `setup-github`, `wizard` for steps only a person can do |
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

## Update

Skills follow the default branch unless you pin them. Run `apm update -g` for one user, or `apm update` for a team, to move to the newest commit. Pin a commit to keep a skill fixed until you change the pin.

## Maintainers

If you wish to contribute, read [docs/maintainers.md](docs/maintainers.md).

## License

MIT. See [LICENSE](LICENSE). Each upstream folder keeps its own LICENSE.
