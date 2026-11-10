# Hidden Unicode in dist/

`task ci` scans every file in `dist/` with `apm audit` for hidden Unicode. `task ci:staged` scans only the staged files under `dist/`.

## What blocks

A WARNING or CRITICAL finding blocks, unless `.apm-audit-baseline.json` accepts it. INFO findings never block. The log lists each blocking finding with its file, line, codepoint, severity and description.

## Fix a finding

- In an in-house skill or an overlay: edit the source under `src/skills/`, then run `task build-apm`.
- In an upstream skill: pin it at its last clean commit with `task update-upstream SKILL=<name> REF=<sha>`, or remove it.

## Accept a finding

Add an entry to `.apm-audit-baseline.json`. Copy `file`, `line` and `codepoint` from the log:

```json
[
  {
    "file": "dist/skills/<skill>/<path>",
    "line": 12,
    "codepoint": "U+200B",
    "reason": "<why the character is safe, in one or two sentences>"
  }
]
```

- An entry matches a finding with the same file, line and codepoint. When an edit moves or changes the line, the finding blocks again.
- An entry with an empty `reason` fails the check.
- The reviewer checks that the `reason` explains why the finding is safe.

An accepted CRITICAL finding still makes a team's `apm install` refuse that bundle, unless the team runs it with `--force`.
