# Ban non-directive comments in scripts and git hooks

We ban non-directive comments in `scripts/` and `.githooks/` and enforce the rule in `scripts/check-comments.py` (`task ci` and `task ci:staged`). Narrative comments drift as code changes and mislead both maintainers and coding agents.

We rejected a `# WHY:` prefix escape hatch because no parser can check whether a comment states a genuine constraint, and coding agents quickly adopt any allowed prefix for routine narration.

Allowed boundaries:
- Line-1 shebangs (`#!`).
- Linter directives (`# shellcheck`, `# noqa`, `# type: ignore`, `# pragma:`, `# pyright:`, `# fmt:`), including a brief reason after the directive.
- Python docstrings (runtime `__doc__`, not `#` comment tokens).
- `.jq` files are printed as an explicit unchecked exception rather than maintaining a custom jq lexer for one filter file, and must still stay comment-free in review.

When a non-obvious constraint matters, place it in the strongest home available, in this order:
1. A test that fails if the constraint breaks.
2. A runtime error or log message.
3. A named variable or function name.
4. A short note in `AGENTS.md` or `docs/`.
