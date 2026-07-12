---
name: create-pr
description: Use when the user explicitly asks to create a pull request for the current branch, or explicitly invokes this skill. Do not use implicitly after ordinary coding tasks.
disable-model-invocation: true
---

# Create PR

## Workflow

1. If `gh` is missing or unauthenticated (`gh auth status` fails), say so and stop — do not fall back to the API or ask for tokens.
2. Resolve base: user-specified branch, else default (`gh repo view --json defaultBranchRef -q .defaultBranchRef.name`; fall back to `git symbolic-ref refs/remotes/origin/HEAD`).
3. If HEAD is the base branch, follow **Starting from the base branch**, then continue from step 4.
4. If an open PR already exists for this branch (`gh pr view`), report its URL and stop.
5. Confirm commits ahead of base (`git log <base>..HEAD`). If none, say so and stop.
6. If the working tree has uncommitted or staged changes, warn they will not be in the PR, then continue.
7. Read the full change set before drafting anything: run `git diff <base>...HEAD` and read the entire patch. Use `git diff <base>...HEAD --stat` only as a file map. Do not write the title or description from commit messages or `--stat` alone. If the branch mixes unrelated work, say so before continuing.
8. Draft title and description from the full patch and all commits on the branch (not only the latest). If a PR template exists (`.github/PULL_REQUEST_TEMPLATE.md`, any capitalization), fill that instead of the format below.
9. Push with `-u` when there is no upstream, or when local commits are unpushed. If the remote has diverged, ask before pushing; never force-push.
10. Create the PR and report the URL. Add `--draft` only when the user asked for a draft.

```bash
gh pr create --base <base> --title "<title>" --body "$(cat <<'EOF'
<body>
EOF
)"
```

## Starting from the base branch

1. Confirm there is something to PR: uncommitted changes, or local commits ahead of the remote base. If neither, say so and stop.
2. Create and switch to a new branch: `<type>/<short-kebab-slug>` (e.g. `fix/null-user-crash`). Local commits ahead of the remote base come along.
3. If there are uncommitted changes, stage and commit them. Message: use the `caveman-commit` skill output as-is; if unavailable, Conventional Commits (imperative, summary under 50 characters).

## Title

- Imperative mood, under 70 characters, no trailing period.
- Use Conventional Commits (`<type>(<scope>): <description>`) when the branch's commits do.

## Description

Write so a reviewer can approve without reading every commit or asking follow-ups. High-level outcome, not a file-by-file walkthrough.

```markdown
## What

What is different after merge, from the reviewer's or user's view — outcome, not implementation. One bullet per logical change on multi-part branches.

## Why

Problem or motivation, enough for someone outside the work. Never "because it was requested". Link the issue when one exists (`Fixes #123`).

## How

Design choices, tradeoffs, rejected alternatives — not mechanics the diff already shows. Skip when the diff is enough.

## Testing

How it was verified: tests added/updated, commands run and results, manual steps. Write "Not tested" rather than omitting this section.
```

Add only when they apply:

- **Breaking changes** — API/schema/config impact and migration steps for callers.
- **Screenshots** — before/after for UI; if you cannot attach them, say they are needed.
- **Notes** — known limitations, deliberate follow-ups, related PRs, rollout.

Rules:

- Scale depth to the diff: one-line fix → two short sentences; multi-commit feature → full sections.
- Call out what a reviewer would otherwise discover mid-review: risky areas, intentional hacks, code that looks wrong but is not.
- No boilerplate, empty checklists, or "Summary of changes" filler. Every section present must carry real content.

## Constraints

- Commit or stage only in the base-branch flow; on a feature branch, create the PR as-is.
