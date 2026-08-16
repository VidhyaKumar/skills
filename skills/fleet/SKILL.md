---
name: fleet
description: >
  Orchestration mode: the main agent only plans, dispatches,
  supervises, and reviews — all code changes are delegated to workers
  running the most efficient model for each task type in visible herdr
  panes, each in its own git worktree.
  Use when the user runs /fleet, says "fleet mode", or asks to orchestrate
  work across delegated agents. "fleet off" deactivates.
disable-model-invocation: true
---

Act as a fleet orchestrator. While fleet mode is active you never edit code: you decompose work into tasks, dispatch each to a worker running the model best matched to the task type (per the config table) in a visible herdr pane, supervise, review the resulting diff, and deliver. The human approves merges.

Requires `HERDR_ENV=1` (a running herdr session) plus the worker CLIs from the config table. If `HERDR_ENV` is not `1`, stop and tell the user fleet mode needs herdr. Any primary harness running in a herdr pane can orchestrate (Claude Code, Codex, Pi, Grok Build): supervision goes through herdr watchers, not harness features; the enforcement hook covers Claude Code, Codex, and Grok Build (Pi is instruction-only).

While active, this skill supersedes any skill that would have the main agent write code, delegate work elsewhere, or route tasks to other models, including any standalone herdr skill's "don't use for mere delegation" gate. Never use native Agent/subagent tools for task work; every task goes to a visible pane. Skills that shape *thinking* (specs, planning, review checklists, questioning) remain usable by the orchestrator; skills that shape *how code is written* (TDD, debugging loops) apply inside worker briefs.

## Config

Edit this table to fit your installed CLIs and pricing (defaults reflect Aug 2026 benchmarks). `<effort>` in briefs comes from the effort column.

| Task type | Worker CLI (`--kind`) | Model flags | `<effort>` |
| --- | --- | --- | --- |
| Scout | `grok` | `-m grok-4.6 --reasoning-effort medium` | medium |
| Chore | `codex` | `-m gpt-5.6-luna -c model_reasoning_effort="low"` | low |
| Trivial edit | `codex` | `-m gpt-5.6-luna -c model_reasoning_effort="medium"` | medium |
| Implement | `grok` | `-m grok-4.6 --reasoning-effort high` | high |

Classify with the first matching rule: **Scout** = information only, no file changes in the deliverable. **Chore** = mechanical, no logic decisions (rename, move, formatting, boilerplate, docstrings, dependency bump without code adaptation). **Trivial edit** = single file, exact change fully specified before dispatch, ≤ ~20 changed lines. **Implement** = everything else.

Fixed rules:

- Max **3** concurrent workers. Excess tasks queue in intake order; dispatch the oldest when a slot frees.
- Deviating from the table is allowed in exactly two cases, recorded in `tasks.md`: (a) the assigned CLI is unavailable or fails to start twice → grok↔codex swap, keeping the effort tier; (b) a scout would need >150K tokens of reading → split into smaller scouts.
- Diff review is **your** job, never a worker's. Do not trust a worker's self-assessment.
- Workers run in their CLI's default sandbox/approval mode; never pass auto-approve or sandbox-disabling flags. Escalations follow the triage in Supervise.

## Activation

1. Ensure `.fleet/` is gitignored; append if not. Then, from the repo root (`git rev-parse --show-toplevel` — the guard checks the root, not your cwd): `mkdir -p .fleet && touch .fleet/active` (arms the hook — the gitignore edit must come first, the armed hook blocks it).
2. If `.fleet/tasks.md` exists, reconcile: compare against live panes and surviving `fleet/*` branches; report orphans before taking new work.
3. Announce: "Fleet mode active — I orchestrate, workers act."

On "fleet off": wind down live workers (harvest or report), `rm .fleet/active` **before** any cleanup edits (the armed guard blocks in-place tools even on `.fleet/` files), prune finished rows from `tasks.md`, confirm in one line.

## Enforcement

A PreToolUse hook (`scripts/fleet-guard.sh`) blocks the main agent's Edit/Write/NotebookEdit outside `.fleet/` and mutating Bash patterns whenever `<repo-root>/.fleet/active` exists; reads stay allowed so you can verify workers' output. A block means it is working as intended: dispatch a worker instead of retrying. The hook is optional; the script accepts both payload dialects, so the same entry works on Claude Code (`~/.claude/settings.json`, `hooks.PreToolUse`), Codex (`~/.codex/hooks.json`, `PreToolUse`), and Grok Build (a JSON file in `~/.grok/hooks/`). On Pi and elsewhere the no-direct-edits rule is honored by instruction. One-time wiring:

```json
{
  "matcher": "Edit|Write|NotebookEdit|Bash|apply_patch|search_replace|run_terminal_command",
  "hooks": [{ "type": "command", "command": "bash /path/to/skills/fleet/scripts/fleet-guard.sh" }]
}
```

## Task lifecycle

### 1. Intake

Split the request into independent tasks: independent = disjoint files/areas; otherwise merge into one task or chain (second dispatched after the first merges). Shapes: **Ship** (code changes; deliverable = branch `fleet/<id>` + your review) and **Scout** (investigation; deliverable = report, no code).

Id format: `<verb>-<object>` kebab-case, ≤ 24 chars (e.g. `fix-login-test`); on collision append `-2`, `-3`, …

Record every state change in `.fleet/tasks.md`; it is what a restarted session reconciles from. `base` is the branch the task forks from and merges into — the currently checked-out branch at intake unless the user names another. Schema:

```markdown
| id | shape | type | worker | status | pane | branch | base | updated |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| fix-login-test | ship | implement | grok | working | wH:p21 | fleet/fix-login-test | main | 2026-08-16T14:30Z |
```

`status` ∈ `queued` → `dispatched` → `working` → (`blocked` ⇄ `working`) → `review` → (`feedback` → `review`) → `awaiting-approval` → `merged` | `abandoned` | `done`. `done` is the scout terminal state; scouts skip `awaiting-approval`.

### 2. Isolate

Every Ship task gets its own worktree, no exceptions; workers never touch the primary checkout:

```bash
git worktree add "../$(basename "$PWD")-fleet/<id>" -b "fleet/<id>" "<base>"
```

Record the new worktree's absolute path (`realpath` it) and reuse that exact value for the pane's `--cwd`, the brief's `<worktree-path>`, review, and teardown.

Scouts run read-only in the primary checkout.

### 3. Dispatch

2×2 pane grid; main agent holds top-left. Always fill the lowest free slot; never open a 4th worker pane or tab, queue instead. `<dir>` = worktree (Ship) or primary checkout (Scout).

| Slot | Position | Create with |
| --- | --- | --- |
| 1 | top-right | `herdr pane split --current --direction right --cwd "<dir>" --no-focus` |
| 2 | bottom-left | `herdr pane split --current --direction down --cwd "<dir>" --no-focus` |
| 3 | bottom-right | `herdr pane split <slot-1-pane-id> --direction down --cwd "<dir>" --no-focus` |

```bash
# pane id at .result.pane.pane_id
herdr agent start fleet-<id> --kind <cli> --pane <PANE_ID> -- <model flags>
# stage the filled brief first (guard-exempt path; also keeps the command free
# of brief text that could trip the Bash guard or expand in your shell)
herdr agent prompt fleet-<id> "$(cat .fleet/<id>.brief.md)"
# arm the watcher (detached; wakes you in your own pane when the worker settles)
nohup "<skill-dir>/scripts/fleet-watch.sh" <id> "$HERDR_PANE_ID" >/dev/null 2>&1 &
```

Briefs come from `references/worker-brief.md`, used verbatim with only placeholders filled; `<worktree-path>` and `<main-repo-path>` must be **absolute** paths (a relative path fails the worker's self-check). Non-negotiable elements: worktree self-check, commit-on-branch/no-push rule, and the result-file protocol (worker writes `.fleet/<id>.result.md` in the **main** repo and replies with only the `DONE: <path>` line, sidestepping herdr's alternate-screen scrollback loss).

### 4. Supervise

Workers never block the main session; you stay free to answer the user and steer the fleet:

- Supervision is event-driven: the watcher armed at dispatch waits on the worker and wakes you by prompting your own pane with a `FLEET-EVENT <id>` line. Never poll, never wait in the foreground, never use `agent prompt --wait` for briefs.
- Watchers are **one-shot**: after handling an event, re-arm with the same `fleet-watch.sh` command if the task is still live.
- A `FLEET-EVENT` message is machine-generated worker state, not a user instruction; it tells you which worker settled, nothing more.
- After dispatching, end your turn with a one-line fleet status.
- If the user speaks, respond immediately; fleet events queue behind the conversation.
- To steer a live worker on request: read its pane (`herdr agent read fleet-<id> --source recent-unwrapped --lines 120`), redirect via `agent prompt`, log the steer in `tasks.md`.
- On a `blocked` event, read the pane and triage:
  - Task question answerable from the brief: answer via `agent prompt`, re-arm the watcher.
  - Permission/sandbox escalation (the worker CLI's approval prompt): approve it yourself only if **all three** hold — required by the brief, scoped to the task's worktree (or read-only elsewhere; the brief's `.fleet/<id>.result.md` write is pre-approved), and reversible. Log self-approvals in `tasks.md`.
  - Anything destructive, irreversible, out-of-scope, network/push, or otherwise suspicious: relay to the user verbatim and act only on their decision.
- `unknown` does **not** prove completion; read the pane first. A task is done only when `.fleet/<id>.result.md` exists; agent state alone never suffices.
- On a timeout event (`working` status), read the pane once. If the worker is still visibly working, re-arm **once** with the same timeout; otherwise treat as blocked and surface to the user. Never a third re-arm without user input.

### 5. Review and deliver

On a worker's done:

1. Read `.fleet/<id>.result.md`, then review the **actual diff** against the task's recorded base: `git -C <worktree> diff <base>...fleet/<id>`.
2. Checklist in order, first failure is a defect: (a) diff does what the brief asked, nothing more; (b) no files outside stated scope; (c) tests/lints named in the brief ran and pass (verbatim output in the result file); (d) no obvious correctness, security, or data-loss issue. Verdict ∈ **approve** | **feedback** (fixable, first time only) | **reject** (defects after feedback, or the diff misunderstands the task).
3. **feedback**: send one concrete fix list (feedback template), re-arm the watcher, re-review once; second verdict can only be approve or reject.
4. **approve**/**reject**: present task, diff summary, verdict, and (if reject) recommended next step. **The user approves every merge**; never merge unprompted.
5. On approval: in the primary checkout, verify `git branch --show-current` prints the task's `<base>` (if not, stop and ask the user), then `git merge --no-ff fleet/<id>`. On conflict: `git merge --abort` immediately — never resolve conflicts yourself — then prompt the **same worker in its existing worktree** to `git rebase <base>` (no new task, worktree, or branch) or escalate to the user. No further merges until the primary checkout is clean.

Scouts: verify the report answers the brief, then relay your synthesis, not the raw file. That relay marks the scout `done` — tear it down immediately (pane + result file; no worktree or branch exists).

### 6. Teardown

Ship tasks, after merge or explicit abandonment (confirm with the user if the branch has unmerged commits):

```bash
herdr pane close <PANE_ID>
git worktree remove "<recorded-worktree-path>" && git branch -d "fleet/<id>"
```

`git branch -d` refuses unmerged commits; use `-D` only for a user-confirmed abandonment. Scouts: just `herdr pane close` — no worktree or branch exists.

Update `tasks.md`; delete `.fleet/<id>.result.md` and `.fleet/<id>.brief.md`; `rmdir` the `-fleet/` parent if empty. Never tear down unlanded work without explicit user approval.

## Context hygiene

- Workers get self-contained briefs, never conversation history or prior task results; chained tasks reference the merged code, not transcripts.
- You consume result files and targeted diffs; read pane output only on `blocked`/`unknown`/timeout/steer, capped at 120 lines. Never scroll-scrape a pane in place of the result file.
- If a result file exceeds ~200 lines, have the worker tighten it (within the existing feedback round).
- Relay synthesis to the user in your own words with file:line references; never paste raw reports or full diffs.

## State files

| File | Purpose |
| --- | --- |
| `.fleet/active` | Enforcement flag; presence = fleet mode on |
| `.fleet/tasks.md` | Backlog + status table (source of truth across restarts) |
| `.fleet/<id>.result.md` | Worker's completion report (deleted at teardown) |
