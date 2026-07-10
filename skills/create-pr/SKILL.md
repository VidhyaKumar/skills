---
name: create-pr
description: Use when the user explicitly asks to create a pull request for the current branch, or explicitly invokes this skill. Do not use implicitly after ordinary coding tasks.
disable-model-invocation: true
---

# Create PR

## Workflow

1. Resolve the base branch: what the user specified, otherwise the default branch (`gh repo view --json defaultBranchRef -q .defaultBranchRef.name`; fall back to `git symbolic-ref refs/remotes/origin/HEAD`).
2. If the current branch is the base branch, follow **Starting from the base branch** below, then continue from step 3.
3. If an open PR already exists for this branch (`gh pr view`), report its URL and stop.
4. Inspect the PR contents: `git log <base>..HEAD` and `git diff <base>...HEAD --stat`. If there are no commits ahead of the base, say so and stop.
5. If there are uncommitted or staged changes, warn that they will not be in the PR before continuing.
6. Push the branch with `-u` if it has no upstream, or if local commits are unpushed.
7. Write the title and description from all commits in the branch — not just the latest. If the repo has a PR template (`.github/PULL_REQUEST_TEMPLATE.md`, any capitalization), fill it instead of the format below.
8. Create the PR and report the URL. Add `--draft` only if the user asked for a draft.

```bash
gh pr create --base <base> --title "<title>" --body "$(cat <<'EOF'
<body>
EOF
)"
```

## Starting from the base branch

1. Confirm there is something to PR: uncommitted changes, or local commits ahead of the remote base. If neither, say so and stop.
2. Create and switch to a new branch named after the change: `<type>/<short-kebab-slug>` (e.g. `fix/null-user-crash`). Local commits ahead of the remote base come along with it.
3. If there are uncommitted changes, stage and commit them. Write the message with the `caveman-commit` skill, using its output as-is; if unavailable, use Conventional Commits (imperative mood, summary under 50 characters).

## Title

- Imperative mood, under 70 characters, no trailing period.
- Follow Conventional Commits (`<type>(<scope>): <description>`) when the branch's commits do.

## Description

Written so a reviewer can approve without reading every commit or asking follow-up questions. High-level, not a file-by-file walkthrough.

```markdown
## What

What is different after merging, from the reviewer's or user's perspective — the outcome, not the implementation. One bullet per logical change on multi-part branches.

## Why

The problem or motivation, with enough context for someone outside the work — never "because it was requested". Link the issue if one exists (`Fixes #123`).

## How

Key design choices, tradeoffs accepted, alternatives rejected — not the mechanics the diff already shows. Skip for trivial changes where the diff speaks for itself.

## Testing

How the change was verified: tests added or updated, commands run and their results, manual steps. Write "Not tested" explicitly rather than omitting the section.
```

Add these sections only when they apply:

- **Breaking changes** — API/schema/config changes and the migration steps callers need.
- **Screenshots** — before/after for UI changes; if you cannot attach them, say they are needed.
- **Notes** — known limitations, follow-up work deliberately left out, related PRs, rollout considerations.

Rules:

- Scale depth to the diff: a one-line fix gets two short sentences; a multi-commit feature gets full sections.
- Surface anything a reviewer would otherwise discover mid-review: risky areas, intentional hacks, code that looks wrong but isn't.
- No boilerplate, no empty checklists, no "Summary of changes" filler — every section present must carry real content.

## Constraints

- Commit or stage only in the base-branch flow above; on a feature branch, the PR is created as-is.
- If the branch mixes unrelated work, call that out before creating the PR.
- Ask before pushing if the remote branch has diverged; never force-push.
- If `gh` is missing or unauthenticated (`gh auth status` fails), say so and stop — do not fall back to the API or ask for tokens.
