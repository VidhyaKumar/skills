---
name: commit-all
description: Use when the user explicitly asks to group all current working tree changes into logical atomic commits, or explicitly invokes this skill. Do not use implicitly for ordinary coding tasks.
disable-model-invocation: true
---

# Commit All

## Gather context

- Inspect modified, staged, and untracked files before proposing commit boundaries.
- Use recent commit history on the current branch as style reference.

## Workflow

1. If there are no changes, say so and stop.
2. Group files into atomic commits (see Grouping rules) and prepare messages using Commit message below.
3. Send a normal user-visible response with a numbered list of intended commits in execution order. For each, show the exact message in a code block (including any body), included files or hunks, and a short rationale. Internal reasoning, tool output, and question-tool options do not count as showing the proposal.
4. Only after that response, explicitly ask for approval and wait for the user's reply. Never call a question or approval tool before sending the complete proposal; if using one, send the proposal as a separate response first.
5. After approval, unstage everything with `git reset HEAD`, then stage and commit each approved group explicitly, one at a time, using its approved message.

Invoking this skill alone is not approval. If a proposed scope or message changes, show the revised proposal and obtain fresh approval before committing it.

## Grouping rules

- Keep related feature work together.
- Split config or dependency changes from product code.
- Split refactors from behavior changes when practical.
- Keep docs separate unless tightly coupled to a code change.
- Isolate bug fixes when they stand on their own.

## Commit message

Use `caveman-commit` and its output as-is. Check all available skills, including plugins and extensions; only if unavailable, use this Conventional Commits fallback:

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
