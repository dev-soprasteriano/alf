# Two kinds of plugin skill: wrapper and in-house

Skills in `plugins/alf/skills/` are either wrappers that point at an upstream asset, or in-house skills that this repo writes and owns. We allow in-house skills because `scripts/update-assets.sh add` copies skills only from an upstream repo with a LICENSE, and this repo's own skills have no upstream, so `git-commit` is written directly in `plugins/alf/skills/git-commit/`.
