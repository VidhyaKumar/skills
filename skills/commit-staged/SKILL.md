---
name: commit-staged
description: Use when the user explicitly asks to generate a commit message for already staged changes and create the commit, or explicitly invokes this skill. Do not use implicitly for ordinary coding tasks.
disable-model-invocation: true
model: sonnet
---

# Commit Staged

Use this skill only when the user explicitly wants the already staged changes committed without staging anything else.

## Workflow

1. Inspect staged changes with `git diff --cached`.
2. Confirm there is at least one staged change. If not, say so and stop.
3. Use recent commits on the current branch as style reference.
4. Produce the message with the `caveman-commit` skill, using its output as-is; only if it is unavailable, use the fallback format below. Match the staged diff only.
5. Execute the commit without staging or modifying additional files.

## Constraints

- Never stage extra files.
- Never widen the commit scope beyond what is already staged.
- If the staged set mixes unrelated work, call that out before committing.

## Commit message

Fallback only. Use this format when `caveman-commit` is not installed — and check the full set of skills, including plugins and extensions, before concluding it is unavailable.

```text
<type>(<scope>): <description>

- bullet explaining why
- second bullet if needed
```

Rules:

- Imperative mood — start the description with a verb (e.g. `add`, `fix`, `remove`, `update`).
- No trailing period in the summary.
- Summary under 50 characters.
- Wrap body lines at 72 characters.
- Explain why, not what.
- For dependency-only commits, list package names and version changes only.

Valid types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`
