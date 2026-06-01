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
2. Security issues
3. Dead code
4. Over-engineering
5. Convention violations
6. Missed edge cases

## Output format

For each finding:

```text
### [Category] severity: high|medium|low

`file:line` — brief description

why it's a problem and how to fix it
```

End with a verdict: `ship it`, `minor fixes needed`, or `needs rework`.

## Review standard

- Prioritize correctness and regressions first.
- Call out concrete behavioral risk, not vague style opinions.
- Mention missing tests when they materially affect confidence.
- If there are no findings, say that explicitly.
