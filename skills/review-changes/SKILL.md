---
name: review-changes
description: Review staged, unstaged, and untracked local working-tree changes. Use when the user asks to review local changes, staged changes, unstaged changes, untracked files, working-tree changes, or wants a pre-commit code review.
disable-model-invocation: true
---

# Review Changes

Use this skill to review the current working tree only: staged, unstaged, and untracked files.

Do not review committed branch diffs unless the user explicitly asks. Do not edit files unless the user explicitly asks for fixes.

## Scope

Review:

- staged changes
- unstaged changes
- untracked files

Skip generated files, vendor code, build output, and lockfiles unless they are directly relevant to the change.

## Process

1. Identify local changes:
   - `git status --short`
   - `git diff --cached --name-only`
   - `git diff --name-only`
   - `git ls-files --others --exclude-standard`

2. Build the review scope.
   - Group files as staged, unstaged, and untracked.
   - Remove generated files, vendor code, build output, and lockfiles unless directly relevant.
   - Note risky areas such as auth, billing, permissions, migrations, data writes, or concurrency.

3. Decide whether to use subagents.
   - Use subagents when the review spans multiple files, multiple domains, or a large diff.
   - Keep the main agent focused on scope control, final judgment, de-duplication, and the final response.
   - Skip subagents for tiny changes where delegation would add more overhead than clarity.

4. Split subagent work by clear review slices when helpful:
   - staged vs. unstaged vs. untracked changes
   - frontend vs. backend vs. shared packages
   - independent feature areas
   - one large file per subagent
   - risky areas first

5. Give each subagent an exact file list or diff slice.
   - Tell subagents to read surrounding code, avoid edits, preserve context discipline, and report only concrete findings or "no findings".
   - Require each subagent to report files reviewed, findings in the standard output format, missing tests or verification gaps, assumptions, and uncertain areas.

6. Review assigned staged changes:
   - Use `git diff --cached`
   - Read surrounding code before commenting.

7. Review assigned unstaged changes:
   - Use `git diff`
   - Read surrounding code before commenting.

8. Review assigned untracked files:
   - Read the full file.
   - Inspect nearby files to understand conventions and integration points.

9. Synthesize the review.
   - Review subagent findings before presenting them.
   - Merge duplicates, drop weak findings, resolve conflicts, and keep the final review concise.

10. Prefer findings over summary.
   - Report concrete bugs, regressions, security issues, or maintainability problems.
   - Avoid low-value style nits unless they materially affect readability or consistency.

## Review Priorities

Flag issues in this order:

1. Bugs, regressions, broken edge cases, race conditions, data loss
2. Security, privacy, auth, permission, injection, or unsafe execution issues
3. Over-engineering, needless complexity, premature abstraction
4. Clever code that hurts readability
5. Convention violations against the local codebase
6. Missing meaningful tests for risky behavior
7. Dead code, unused exports, or unreachable paths
8. Poor names that obscure behavior or side effects
9. Excessive prop drilling or misplaced data fetching/mutations
10. Spaghetti branching or feature-specific logic leaking into shared paths

## Code Quality Bar

Prefer direct, boring, maintainable code.

Push back on:

- nested conditionals that could be guard clauses
- `else` after `return` or `throw`
- unnecessary `let`
- non-null assertions where narrowing would work
- `any`, `unknown`, casts, or optionality that hide the real contract
- nested ternaries
- pass-through helpers, identity wrappers, or abstractions that do not simplify anything
- one-off special cases inserted into unrelated flows
- duplicated logic instead of using a canonical helper
- files or components growing beyond a healthy size without decomposition

Do not request churn when the code is already clear.

## Output Format

Lead with findings. Skip empty categories. If there are no findings, say that clearly.

For each finding:

```text
### [Category] severity: 🔴|🟡|🔵

WHAT: `file:line` - concise issue

WHY: concrete risk or maintainability cost

HOW: specific fix or simpler structure
```

End with:

```text
Verdict: 🚀 ship it | ⚠️ minor fixes needed | ⛔ needs rework

Tests: mention tests reviewed, missing tests, or why tests were not needed.
Scope: staged, unstaged, and untracked changes reviewed.
```
