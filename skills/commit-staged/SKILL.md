---
name: commit-staged
description: Use when the user explicitly asks to generate a commit message for already staged changes and create the commit, or invokes $commit-staged. Do not use implicitly for ordinary coding tasks.
disable-model-invocation: true
---

# Commit Staged

Use this skill only when the user explicitly wants the already staged changes committed without staging anything else.

## Workflow

1. Inspect staged changes with `git diff --cached`.
2. Confirm there is at least one staged change. If not, say so and stop.
3. Use recent commits on the current branch as style reference.
4. Draft a Conventional Commit message that matches the staged diff only.
5. Execute the commit without staging or modifying additional files.

## Constraints

- Never stage extra files.
- Never widen the commit scope beyond what is already staged.
- If the staged set mixes unrelated work, call that out before committing.

## Commit message format

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
