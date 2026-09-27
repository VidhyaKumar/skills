---
name: commit-staged
description: Use when the user explicitly asks to generate a commit message for already staged changes and create the commit, or explicitly invokes this skill. Do not use implicitly for ordinary coding tasks.
disable-model-invocation: true
---

# Commit Staged

## Workflow

1. Inspect `git diff --cached`. If nothing is staged, say so and stop.
2. Use recent commits on the current branch as style reference and prepare the message using Commit message below.
3. Send a normal user-visible response showing the exact message in a code block (including any body) and the staged files. Flag unrelated work in the staged set. Internal reasoning, tool output, and question-tool options do not count as showing the proposal.
4. Only after that response, explicitly ask for approval and wait for the user's reply. Never call a question or approval tool before sending the complete proposal; if using one, send the proposal as a separate response first.
5. After approval, commit with the approved message and reply with the short hash and summary.

## Constraints

- Commit only the existing staged changes; never stage or modify additional files.
- Invoking this skill alone is not approval.
- If the proposed scope or message changes, show the revised proposal and obtain fresh approval before committing it.

## Commit message

Use `caveman-commit` and its output as-is. Check all available skills, including plugins and extensions; only if unavailable, use this Conventional Commits fallback:

```text
<type>(<scope>): <description>

- why, only when the summary doesn't make it obvious
```

Rules:

- Imperative mood — start the description with a verb (e.g. `add`, `fix`, `remove`, `update`).
- No trailing period in the summary.
- Summary under 50 characters.
- Wrap body lines at 72 characters.
- Add a body only for a non-obvious why or a breaking change; explain why, not what.
- For dependency-only commits, list package names and version changes only.

Valid types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`
