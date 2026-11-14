# Agent instruction recommendations

Some rules work better as a line in your repo's instruction file than as a skill. This page says where each kind of rule belongs, and gives blocks to copy.

The instruction file is `AGENTS.md`, `CLAUDE.md` or `.github/copilot-instructions.md`. The harness loads it in every session.

## Where a rule belongs

Choose by how often the rule applies and how strictly it must hold.

| Place | Loaded | Use for |
| --- | --- | --- |
| Instruction file | In every session. Each line costs context every time. | A short rule that applies to most sessions. |
| Skill | Only when a task or the user calls it. | A procedure with several steps, or reference material that few sessions need. |
| Repo file with a fixed role: `.github/pull_request_template.md`, `CODING_STANDARDS.md` | When the harness or a skill reads it. | A template or a standard that people and tools share. |
| Hook or CI check | On every commit or pull request, with no agent involved. | A rule that must hold. |

An instruction is advice to the agent. A hook is a rule. When an agent keeps breaking an instruction, move the rule to a hook or a CI check.

## Commits

Put the commit message rule in the instruction file, not in a skill:

- The rule is short and applies to every commit.
- Both harnesses commit when you ask, and neither loads a skill first. `implement` also commits without calling `git-commit`. The skill's style applies only in the sessions that load it.
- The `git-commit` skill bans credit lines for AI tools, such as `Co-Authored-By`. Claude Code adds one by default. The ban holds only in the sessions that load the skill.

Copy this block into the instruction file:

```markdown
## Commits

- Subject: imperative, capital first letter, no full stop, 50 characters where possible, 72 at most.
- Name what changed. Do not list files.
- Add a body only when the reason is not clear from the subject. Say why, not how. Wrap at 72.
- One logical change per commit.
- End the body with the issue: `Closes #<number>`.
- Never add a credit line for an AI tool, such as `Co-Authored-By`.
```

The last line carries over the ban from `git-commit`. Delete it if your repo accepts such lines.

With this block in place, you can leave `git-commit` out of your `apm.yml`. If the format must hold, add a `commit-msg` hook, or a CI check on the PR title.

### What makes a commit message good

- **Subject.** Say what changed and name the thing: `Add retry to the upload client`, not `Update files`. Use the imperative mood.
- **Body.** Say why the change was made and what it affects. Leave out how: the diff shows that.
- **Scope.** One logical change per commit. A subject that needs "and" describes two commits.
- **Prefixes.** Use Conventional Commits (`feat:`, `fix:`) only when a tool reads them, such as a release or changelog generator.
- **Squash merges.** The PR title becomes the commit subject. Apply the subject rule to PR titles.

The `git-commit` skill follows the subject rule. It differs on two points: it writes one line unless you ask for more, and it has no place for the issue reference.

## Pull request body

Put the PR body template in `.github/pull_request_template.md`. GitHub fills it in for people, Copilot CLI's `/pr create` follows it, and an agent that opens a PR can read it.

The `pr` skill carries its own template: summary diagram, before/after evidence and merge danger. Keep the skill for its guidance on how to fill in each section. If your repo has its own template, add one line to the instruction file:

```markdown
## Pull requests

- Write the PR body from `.github/pull_request_template.md`.
```

## Coding standards

Put coding standards in `CODING_STANDARDS.md`, not in the instruction file. The `code-review` skill reads that file at review time, so the rules cost no context while the agent builds. Turn a mechanical rule, such as a banned API or an import shape, into a lint rule.

## Keep the instruction file short

- Add a rule only when an agent got something wrong without it.
- Point to a file for anything longer than a few lines.
- Run `/retro` after a hard session. It finds instructions that change nothing, and rules that belong in a check.
- In Copilot CLI, `/chronicle improve` proposes edits to `.github/copilot-instructions.md` from your past sessions.
