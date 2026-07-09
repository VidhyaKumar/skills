---
name: create-pr
description: Use when the user explicitly asks to create a pull request for the current branch, or explicitly invokes this skill. Do not use implicitly after ordinary coding tasks.
disable-model-invocation: true
---

# Create PR

Use this skill only when the user explicitly wants a pull request created for the current branch.

## Workflow

1. Confirm the current branch is not the default branch. If it is, say so and stop.
2. Inspect what the PR will contain: `git log <default-branch>..HEAD` and `git diff <default-branch>...HEAD --stat`.
3. Confirm there is at least one commit ahead of the default branch. If not, say so and stop.
4. Push the branch with `-u` if it has no upstream, or if local commits are unpushed.
5. Write the title and description in the format below, based on all commits in the branch — not just the latest.
6. Create the PR with `gh pr create` and report the URL.

## Title

- Imperative mood, under 70 characters, no trailing period.
- Follow Conventional Commits (`<type>(<scope>): <description>`) when the branch's commits do.

## Description

Three sections, each succinct and high-level. No file-by-file walkthroughs, no restating the diff.

```markdown
## What

One or two sentences: the change from the user's or reviewer's perspective.

## Why

The problem or motivation. Link the issue if one exists (`Fixes #123`).

## How

The approach in a few sentences or bullets: the key decision(s), not the mechanics.
```

Rules:

- Each section fits in 1–3 sentences or up to 3 bullets.
- **What** states the outcome, not the implementation.
- **Why** explains motivation — never "because it was requested".
- **How** covers only decisions a reviewer needs context for; skip it entirely for trivial changes where the diff speaks for itself.
- No boilerplate, no checklists, no "Summary of changes" filler.

## Constraints

- Never commit or stage anything; the branch is created as-is.
- If the branch mixes unrelated work, call that out before creating the PR.
- Ask before pushing if the remote branch has diverged.
