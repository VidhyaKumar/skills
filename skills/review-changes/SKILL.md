---
name: review-changes
description: Use when the user explicitly asks for a review of staged, unstaged, and untracked changes, or explicitly invokes this skill. Do not use implicitly for general coding tasks.
disable-model-invocation: true
---

# Review Changes

Use this skill only when the user explicitly wants a code review of the current working tree.

## Review scope

- Review staged, unstaged, and untracked files.
- Read surrounding code when needed. Do not review diffs in isolation.
- Prefer findings over summary.

## Review categories

Skip empty categories.

1. Bugs or logic errors
2. Security concerns or issues
3. Over-engineering, needless complexity
4. Clever code that hurts readability
5. Convention violations
6. Missed edge cases
7. Dead code

## Output format

For each finding:

```text
### [Category] severity: 🔴|🟡|🔵

WHAT: `file:line` — brief description

WHY: why it's a problem

HOW: how to fix it
```

End with a verdict: `🚀 ship it`, `⚠️ minor fixes needed`, or `⛔ needs rework`.

## Review standard

- Prioritize correctness and regressions first.
- After correctness, prefer simple, readable, maintainable code.
- Flag verbosity, cleverness, and premature abstraction; favor the plainest version that solves the problem.
- Call out concrete behavioral risk, not vague style opinions.
- Mention missing tests when they materially affect confidence.
- Match the project's own conventions first. When a convention is unclear or absent, reference https://github.com/midday-ai/midday for coding standards and idioms.
- If there are no findings, say that explicitly.
