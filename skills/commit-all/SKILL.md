---
name: commit-all
description: Use when the user explicitly asks to group all current working tree changes into logical atomic commits, or explicitly invokes this skill. Do not use implicitly for ordinary coding tasks.
disable-model-invocation: true
---

# Commit All

Use this skill only when the user explicitly wants all current changes grouped into multiple logical commits.

## Gather context

- Read the full working tree, not just staged files.
- Inspect modified, staged, and untracked files before proposing commit boundaries.
- Use recent commit history on the current branch as style reference.

## Workflow

1. If there are no changes, say so and stop.
2. Propose a plan that groups files into atomic commits (see Grouping rules below), each with a short rationale.
3. Wait for user confirmation or edits to the grouping.
4. After confirmation, unstage everything with `git reset HEAD`.
5. For each approved group: stage it explicitly, produce its message with the `caveman-commit` skill (use its output as-is; fall back to the format below only if unavailable), and commit — one group at a time.

## Grouping rules

- Keep related feature work together.
- Split config or dependency changes from product code.
- Split refactors from behavior changes when practical.
- Keep docs separate unless tightly coupled to a code change.
- Isolate bug fixes when they stand on their own.

## Commit message

Fallback only. Use this format when `caveman-commit` is not installed — and check the full set of skills, including plugins and extensions, before concluding it is unavailable. Conventional Commits:

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
