# Two kinds of skill: wrapper and in-house

Skills in `src/skills/` are either wrappers that point at an upstream skill, or in-house skills that this repo writes and owns. We allow in-house skills because `scripts/update-upstream.sh add` copies skills only from an upstream repo with a LICENSE, and this repo's own skills have no upstream, so `git-commit` is written directly in `src/skills/git-commit/`.
