# Worker brief template

Fill every `<placeholder>`; `<worktree-path>` and `<main-repo-path>` must be absolute paths. Send as a single `herdr agent prompt` message via a quoted heredoc so backticks survive.

## Ship task

```
You are worker <id> in a supervised fleet. Work ONLY inside this worktree.

SELF-CHECK FIRST: run `pwd -P` and `git rev-parse --show-toplevel`. Both must
resolve under <worktree-path> and `git branch --show-current` must print
fleet/<id>. If any check fails, STOP immediately and reply exactly:
BLOCKED: wrong worktree.

TASK:
<task description — concrete, self-contained; include acceptance criteria and
the files/areas involved. Assume the worker has no other context.>

CONSTRAINTS:
- Commit your work on branch fleet/<id> in small logical commits. Do NOT push,
  do NOT open PRs, do NOT merge, do NOT switch branches.
- Touch only files this task requires. Sole exception outside the worktree:
  the result file in step 1 of WHEN DONE.
- Run the project's tests/linters relevant to your change before finishing:
  <test/lint commands, if known>
- Use <effort> reasoning effort. If truly stuck, say so rather than guessing.

WHEN DONE:
1. Write a completion report to <main-repo-path>/.fleet/<id>.result.md
   containing: what changed (files + why), test/lint results verbatim,
   anything you could not do, and any follow-ups you noticed but did not act on.
2. Reply with ONLY this line: DONE: <main-repo-path>/.fleet/<id>.result.md
```

## Scout task

```
You are scout <id> in a supervised fleet. This is a READ-ONLY investigation:
make no file modifications, no commits, no installs. Sole exception: the
result file in step 1 of WHEN DONE.

QUESTION:
<what to find out — specific, answerable, self-contained>

SCOPE:
- Look at: <paths / areas / commands to run>
- Keep total reading under ~150K tokens; sample representative files rather
  than exhaustively reading large directories.

WHEN DONE:
1. Write your full report to <main-repo-path>/.fleet/<id>.result.md —
   conclusions first, then evidence with file:line references. Answer the
   question directly; state uncertainty explicitly instead of hiding it.
2. Reply with ONLY this line: DONE: <main-repo-path>/.fleet/<id>.result.md
```

## Feedback round (max one per task)

Ship version below. For a scout, drop the branch/commit clause: "Fix ONLY the
items below by updating <main-repo-path>/.fleet/<id>.result.md, and reply
DONE: <main-repo-path>/.fleet/<id>.result.md again."

```
Review of your work found issues. Fix ONLY the items below on branch
fleet/<id>, commit, update <main-repo-path>/.fleet/<id>.result.md, and reply
DONE: <main-repo-path>/.fleet/<id>.result.md again.

ISSUES:
1. <file:line — concrete defect and expected fix>
2. ...
```
