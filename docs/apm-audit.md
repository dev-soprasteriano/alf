# Hidden Unicode in dist/

`task ci` scans every file in `dist/` with `apm audit` for hidden Unicode. `task ci:staged` scans only the staged files under `dist/`.

## What blocks

Every WARNING or CRITICAL finding blocks. Findings cannot be accepted: fix them. INFO findings never block. The log lists each blocking finding with its file, line, codepoint, severity and description.

## Fix a finding

- In an in-house skill or an overlay: edit the source under `src/skills/`, then run `task build-apm`.
- In an upstream skill: pin it at its last clean commit with `task update-upstream SKILL=<name> REF=<sha>`, or remove it.
