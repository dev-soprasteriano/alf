# AGENTS.md

Rules for agents working in this repo. Read them before changing `plugins/alf/`.

## Layout

- `plugins/alf/assets/<upstream>/<skill>/`: a byte-for-byte copy of one upstream skill folder.
- `plugins/alf/assets/<upstream>/LICENSE` and `PIN.md`: the upstream's license, and one row per asset with its commit and whether it is pinned.
- `plugins/alf/skills/<skill>/SKILL.md`: a wrapper. Its frontmatter is copied from the asset, and its body points at the asset. A wrapper can have a different name from its asset folder; the `Wrapper` column in `PIN.md` gives that name.
- `scripts/update-assets.sh`: changes assets. `task update-assets` and the weekly workflow both run it.

## Editing rules

- Change files under `plugins/alf/assets/` through `scripts/update-assets.sh`.
- Add local instructions to a wrapper between its `<!-- overlay:start -->` and `<!-- overlay:end -->` markers. The script regenerates the frontmatter and the pointer line.
- Write files in this repo without AI disclaimers.

## Adding or updating assets, or checking a PR that touches them

1. **License.** Read the upstream `LICENSE`. Tell the user its name and copyright line. If it is new, or changed since the last pin, say so. If it is missing, or not permissive (MIT, Apache-2.0, BSD-2/3-Clause, ISC, Unlicense, CC0), warn the user and suggest aborting that change.
2. **Dependencies.** For every changed asset, list the other skills its files call or link to: any phrase that asks for another skill to be called or used by name (for example `call ... with "name"` or `the name skill`), `/name` references to skills, and relative links that leave the asset folder. Each one must be an asset with a wrapper in `plugins/alf/skills/`. Only names of skills count.
3. **Missing dependencies.** Report each missing one, and offer to add it as an asset.
4. **Report, then ask.** Summarise what you found, and ask before committing or pushing.

## Commands

- `task update-assets` moves unpinned assets to latest.
- `task update-assets SKILL=<name>` moves one asset to latest.
- `task update-assets SKILL=<name> REF=<sha or tag>` pins one asset.
- Add `DRY_RUN=1` to any of these to print the plan.
- `scripts/update-assets.sh add <upstream> <url> <path>...` copies new assets in and writes the files.

Each update opens a PR. Its description tells the reviewer to check LICENSE changes and missing linked assets.
