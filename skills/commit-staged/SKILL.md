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
4. Compose the commit message (see Commit message below), matching the staged diff only.
5. Execute the commit without staging or modifying additional files.

## Constraints

- Never stage extra files.
- Never widen the commit scope beyond what is already staged.
- If the staged set mixes unrelated work, call that out before committing.

## Commit message

Before composing the commit message, check if a `caveman-commit` skill is available. Check the full set of available skills, including any provided by plugins or extensions — not just a single skill directory. If it is available, invoke it and use the message it produces as-is — its format overrides everything below. The format below applies only when `caveman-commit` is unavailable.

```text
<type>(<scope>): <description>

- bullet explaining why
- second bullet if needed
```

Rules:

- Imperative mood.
- No trailing period in the summary.
- Summary under 50 characters.
- Wrap body lines at 72 characters.
- Explain why, not what.
- For dependency-only commits, list package names and version changes only.

Valid types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`
