# Hidden Unicode in dist/

`task ci` scans every file in `dist/` with `apm audit` for hidden Unicode. `task ci:staged` scans only the staged files under `dist/`.

## What blocks

| Severity | Blocks | Accept it? |
| --- | --- | --- |
| CRITICAL, WARNING | Yes | No. Fix it. |
| INFO | Never | Not needed. |

The log lists each blocking finding with its file, line, codepoint, severity and description.

## Fix a finding

| Finding is in | Fix |
| --- | --- |
| An in-house skill or an overlay | Edit the source under `src/skills/`, then run `task build-apm`. |
| An upstream skill | Pin it at its last clean commit with `task update-upstream SKILL=<name> REF=<sha>`, or remove it. |
