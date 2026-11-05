# Agentic Lifecycle Foundation

The `alf` plugin packages a set of engineering and productivity skills. Each one is a byte-for-byte copy of an upstream skill, pinned to a commit under `plugins/alf/assets/`. A wrapper skill under `plugins/alf/skills/` points at that copy and can add local instructions after the upstream text.

## Install

Pick the agent you use.

**GitHub Copilot CLI**

```
copilot plugin marketplace add olillevik/alf
copilot plugin install alf@alf
```

**Claude Code** (2.1.275 or later)

In a session:

```
/plugin install alf --marketplace olillevik/alf
```

From a terminal:

```
claude plugin install alf --marketplace olillevik/alf
```

## Updating

Install [go-task](https://taskfile.dev) once (`brew install go-task`), then:

- `task update-assets` moves unpinned assets to the latest upstream revision and opens a PR.
- `task update-assets SKILL=<name>` moves one asset to latest.
- `task update-assets SKILL=<name> REF=<sha or tag>` pins one asset to a revision.
- `DRY_RUN=1` on any of these prints the plan.

A GitHub Actions job runs `task update-assets` every Monday at 06:00 UTC. `AGENTS.md` lists the rules agents follow when they touch assets.
