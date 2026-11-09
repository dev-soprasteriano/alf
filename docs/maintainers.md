# Maintaining alf

For people who change this repo. To use the skills, read the [README](../README.md). Editing rules and the license check are in [AGENTS.md](../AGENTS.md).

Skills live in two places. `src/skills/` holds in-house skills and wrappers. `src/upstream/` holds copies of upstream skills. `dist/` is generated: never edit it.

## Set up a clone

```sh
brew install go-task uv jq
task hooks:install
```

Run `task --list` for the commands and their options. Once hooks are installed, each commit runs `task ci:staged`. `task ci` runs the full set that CI runs.

## Build after a change

After any change under `src/`, run `task build-apm` and commit `dist/` with it. `task ci` fails when `dist/` is stale.

## Add an in-house skill

1. Create `src/skills/<name>/SKILL.md` with `name` and `description` in its frontmatter.
2. If it calls or names other skills, list them in `src/skill-dependencies.txt`. The build fails on any unlisted name.
3. Build and commit (see above).

## Add an upstream skill

1. Run `scripts/update-upstream.sh add <upstream> <url> <path>[=<wrapper>]`. `<path>` is the skill folder in the upstream repo. `=<wrapper>` sets the wrapper name when it differs from the folder name. The script stops if the upstream has no LICENSE on its default branch.
2. Check the skill's LICENSE and linked skills, as [AGENTS.md](../AGENTS.md) describes. Add any missing skill the same way.
3. Build and commit (see above).

## Extend an upstream skill

Add instructions to the wrapper's `SKILL.md`, between `<!-- overlay:start -->` and `<!-- overlay:end -->`. The update script keeps the overlay. For an example, see `src/skills/ask-alf/SKILL.md`. Then build and commit (see above).

## Update upstream skills

The weekly workflow, `.github/workflows/update-upstream.yml`, runs `task update-upstream` every Monday. It pushes `upstream/weekly-update` and opens or updates its pull request. To run it now, start the workflow by hand from the Actions tab.

To hold a skill, pin it: `task update-upstream SKILL=<name> REF=<sha or tag>`. The weekly job skips pinned skills. To release it, run `task update-upstream SKILL=<name>`.

## Review an update pull request

1. Check the LICENSE and linked skills in the pull request, as [AGENTS.md](../AGENTS.md) describes.
2. Wait for the `scan` check. It runs `task ci` on the branch. For each finding, fix it, or accept it in `.skillspector-baseline.yaml`. See [docs/skillspector.md](skillspector.md).
3. Approve after the last push. The branch rule below requires it.

## Branch rule

`main` requires the `scan` check to pass and one approving review, given after the last push. GitHub's repository settings hold this rule, not the repo. Check it again after a fork or a recreation of the repo.
