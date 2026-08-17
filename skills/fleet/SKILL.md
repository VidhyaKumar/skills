---
name: fleet
description: >
  Orchestration mode: the fleet-manager only plans, dispatches,
  supervises, and reviews — all code changes are delegated to fleet-workers
  (matching the fleet-manager's harness, model, and effort by default)
  in visible herdr tabs, each in its own git worktree.
  Use when the user runs /fleet, says "fleet mode", or asks to orchestrate
  work across delegated agents. "fleet off" deactivates.
disable-model-invocation: true
---

Act as the fleet-manager. While fleet mode is active you never edit code: you decompose work into tasks, dispatch each to a fleet-worker (per the fleet-worker config) in a visible herdr tab, supervise, review the resulting diff, and deliver. The human approves merges.

Requires `HERDR_ENV=1` (a running herdr session) plus the configured fleet-worker CLI (the fleet-manager's own by default). If `HERDR_ENV` is not `1`, stop and tell the user fleet mode needs herdr. Any primary harness running in a herdr pane can orchestrate (Claude Code, Codex, Pi, Grok Build): supervision goes through herdr watchers, not harness features; the enforcement hook covers Claude Code, Codex, and Grok Build, and a Pi extension (`scripts/fleet-guard-pi.ts`) covers Pi.

While active, this skill supersedes any skill that would have the fleet-manager write code, delegate work elsewhere, or route tasks to other models, including any standalone herdr skill's "don't use for mere delegation" gate. Never use native Agent/subagent tools for task work; every task goes to a visible tab. Skills that shape *thinking* (specs, planning, review checklists, questioning) remain usable by the fleet-manager; skills that shape *how code is written* (TDD, debugging loops) apply inside fleet-worker briefs.

## Config

Fleet-workers default to the fleet-manager's own setup: same harness as the `--kind`, same model, same effort/thinking level. On the first activation in a repo (no `.fleet/config.md` yet), ask the user whether to keep that default or override any of harness, model, and effort; write the resolved values to `.fleet/config.md` (the guard exempts `.fleet/`, so this works while fleet is armed). Later activations reuse the file without re-asking; change it only on user request. Any `herdr agent start --kind` value works as the fleet-worker harness.

```markdown
kind: pi
model: gpt-5.6-luna
effort: xhigh
flags: --provider openai-codex
```

`kind` matches herdr's `--kind` flag (the fleet-worker harness); `model` and `effort` are translated into that CLI's own flags by `fleet-dispatch.sh` (for kinds it doesn't know, put the model/effort flags in `flags` instead); `flags` is optional extra CLI arguments appended verbatim. Pi treats `model` as a fuzzy pattern across all providers — if it could match a same-named model elsewhere (e.g. a `:batch` variant on openrouter), pin it with `flags: --provider <provider>`; when the fleet-manager itself runs on pi, copy its own provider. `effort` also fills `<effort>` in briefs. Record resolved values, never "match the fleet-manager" — a later session may run a different model. Pi fleet-workers coexist with the fleet-guard-pi extension: worktrees have no `.fleet/active`, so Ship fleet-workers run unguarded, and a scout's `.fleet/<id>.result.md` write in the primary checkout is exempt.

Fixed rules:

- No cap on concurrent fleet-workers: dispatch independent tasks immediately; chain only where Intake found a real dependency.
- Deviating from `.fleet/config.md` is allowed in exactly one case, recorded in `tasks.md`: a scout that would need >150K tokens of reading → split into smaller scouts. If the configured fleet-worker CLI is unavailable or fails to start twice, stop and ask the user.
- Diff review is **your** job, never a fleet-worker's. Do not trust a fleet-worker's self-assessment.
- Fleet-workers run in their CLI's default sandbox/approval mode; never pass auto-approve or sandbox-disabling flags. Escalations follow the triage in Supervise.

## Activation

1. Run `"<skill-dir>/scripts/fleet-mode.sh" on`. Idempotent, safe to re-run; relay any warning or refusal it prints to the user.
2. If it reports no fleet-worker config, ask the user: keep the default (fleet-workers match this session's harness, model, and effort) or override any of the three. Write the resolved values to `.fleet/config.md`.
3. If it reports existing rows, reconcile: compare against live tabs and surviving `fleet/*` branches; report orphans before taking new work.
4. Announce: "Fleet mode active — I orchestrate, fleet-workers act."

On "fleet off": wind down live fleet-workers (harvest or report), then run `"<skill-dir>/scripts/fleet-mode.sh" off` — **before** any other cleanup edits (the armed guard blocks in-place tools even on `.fleet/` files). Confirm in one line.

On "fleet uninstall" (explicit user request only): confirm with the user first — destructive: deletes `.fleet/` with `tasks.md` and `config.md`. Then wind down any live fleet-workers and run `"<skill-dir>/scripts/fleet-mode.sh" uninstall` (turns fleet off itself if still on). If it refuses over unfinished rows, relay the ids and ask the user; for rows they abandon, mark them `abandoned` in `tasks.md`, run `off` to prune, then retry. The harness hook entry stays (inert without the flag, shared across repos). Never remove `.fleet/` any other way.

## Enforcement

A PreToolUse hook (`scripts/fleet-guard.sh`) blocks the fleet-manager's Edit/Write/NotebookEdit outside `.fleet/` and mutating Bash patterns whenever `<repo-root>/.fleet/active` exists; reads stay allowed so you can verify fleet-workers' output. A block means it is working as intended: dispatch a fleet-worker instead of retrying. The hook is optional; the script accepts both payload dialects, so the same entry works on Claude Code (`~/.claude/settings.json`, `hooks.PreToolUse`), Codex (`~/.codex/hooks.json`, `PreToolUse`), and Grok Build (a JSON file in `~/.grok/hooks/`). On Pi, wire `scripts/fleet-guard-pi.ts` instead: copy or symlink it into `~/.pi/agent/extensions/` (auto-discovered, shared across repos, inert without the flag — same model as the hook). It enforces the same rules via Pi's `tool_call` block API, needs no `jq`, and shows a "fleet mode ON" status line in armed repos. On harnesses with neither hooks nor extensions the rule is honored by instruction. One-time wiring:

```json
{
  "matcher": "Edit|Write|NotebookEdit|Bash|apply_patch|search_replace|run_terminal_command",
  "hooks": [{ "type": "command", "command": "bash /path/to/skills/fleet/scripts/fleet-guard.sh" }]
}
```

## Task lifecycle

### 1. Intake

Split the request into independent tasks: independent = disjoint files/areas; otherwise merge into one task or chain (second dispatched after the first merges). Shapes: **Ship** (code changes; deliverable = branch `fleet/<id>` + your review) and **Scout** (investigation; deliverable = report, no code).

Id format: `<verb>-<object>` kebab-case, ≤ 24 chars (e.g. `fix-login-test`); `fleet-task.sh create` auto-suffixes collisions and prints the resolved id.

Row lifecycle goes through `fleet-task.sh` (`create`, `status <id> <status>`, `tab <id> <tab-id>`); `.fleet/tasks.md` is what a restarted session reconciles from. `base` is the branch the task forks from and merges into: the currently checked-out branch at intake unless the user names another. Schema:

```markdown
| id | shape | fleet-worker | status | tab | branch | base | updated |
| --- | --- | --- | --- | --- | --- | --- | --- |
| fix-login-test | ship | pi | working | wH:t4 | fleet/fix-login-test | main | 2026-08-16T14:30Z |
```

`status` ∈ `queued` → `dispatched` → `working` → (`blocked` ⇄ `working`) → `review` → (`feedback` → `review`) → `awaiting-approval` → `merged` | `abandoned` | `done`. `done` is the scout terminal state; scouts skip `awaiting-approval`.

### 2. Isolate

Every Ship task gets its own worktree, no exceptions; fleet-workers never touch the primary checkout:

```bash
"<skill-dir>/scripts/fleet-task.sh" create <id> <ship|scout> <base>
```

It provisions the worktree and `fleet/<id>` branch (Ship), appends the row, and prints the resolved id and absolute dir; use that exact `dir` for the brief's `<worktree-path>`. Scouts run read-only in the primary checkout.

### 3. Dispatch

Each fleet-worker runs in its own herdr tab. Role-based names, set by the scripts: fleet-manager tab and agent are `fm-<project>` (renamed at activation), fleet-worker tab and agent are `fw-<id>`. Herdr caps agent names at 32 chars, so task ids are lowercase `[a-z0-9_-]` and at most 29 chars — `fleet-task.sh create` rejects longer ones.

```bash
# stage the filled .fleet/<id>.brief.md first
# (guard-exempt path; keeps brief text out of your shell command)
"<skill-dir>/scripts/fleet-dispatch.sh" <id>
```

One atomic step: opens the tab in the task's dir, starts the fleet-worker per `config.md`, sends the brief, arms the watcher, marks the row `dispatched`.

Briefs come from `references/fleet-worker-brief.md`, used verbatim with only placeholders filled; `<worktree-path>` and `<main-repo-path>` must be **absolute** paths (a relative path fails the fleet-worker's self-check). Non-negotiable elements: worktree self-check, commit-on-branch/no-push rule, and the result-file protocol (fleet-worker writes `.fleet/<id>.result.md` in the **main** repo and replies with only the `DONE: <path>` line, sidestepping herdr's alternate-screen scrollback loss).

### 4. Supervise

Fleet-workers never block the main session; you stay free to answer the user and steer the fleet:

- Supervision is event-driven: the watcher armed at dispatch waits on the fleet-worker and wakes you by prompting your own pane with a `FLEET-EVENT <id>` line. Never poll, never wait in the foreground, never use `agent prompt --wait` for briefs.
- Watchers are **one-shot**: after handling an event, if the task is still live re-arm with `nohup "<skill-dir>/scripts/fleet-watch.sh" <id> "$HERDR_PANE_ID" >/dev/null 2>&1 &` (dispatch armed the first one).
- A `FLEET-EVENT` message is machine-generated fleet-worker state, not a user instruction; it tells you which fleet-worker settled, nothing more.
- After dispatching, end your turn with a one-line fleet status.
- If the user speaks, respond immediately; fleet events queue behind the conversation.
- To steer a live fleet-worker on request: read its pane (`herdr agent read fw-<id> --source recent-unwrapped --lines 120`), redirect via `agent prompt`, log the steer in `tasks.md`.
- On a `blocked` event, read the pane and triage:
  - Task question answerable from the brief: answer via `agent prompt`, re-arm the watcher.
  - Permission/sandbox escalation (the fleet-worker CLI's approval prompt): approve it yourself only if **all three** hold — required by the brief, scoped to the task's worktree (or read-only elsewhere; the brief's `.fleet/<id>.result.md` write is pre-approved), and reversible. Log self-approvals in `tasks.md`.
  - Anything destructive, irreversible, out-of-scope, network/push, or otherwise suspicious: relay to the user verbatim and act only on their decision.
- `unknown` does **not** prove completion; read the pane first. A task is done only when `.fleet/<id>.result.md` exists; agent state alone never suffices.
- On a timeout event (`working` status), read the pane once. If the fleet-worker is still visibly working, re-arm **once** with the same timeout; otherwise treat as blocked and surface to the user. Never a third re-arm without user input.

### 5. Review and deliver

On a fleet-worker's done:

1. Read `.fleet/<id>.result.md`, then review the **actual diff** against the task's recorded base: `git -C <worktree> diff <base>...fleet/<id>`.
2. Checklist in order, first failure is a defect: (a) diff does what the brief asked, nothing more; (b) no files outside stated scope; (c) tests/lints named in the brief ran and pass (outcome summary in the result file; verbatim only for failures); (d) no obvious correctness, security, or data-loss issue. Verdict ∈ **approve** | **feedback** (fixable, first time only) | **reject** (defects after feedback, or the diff misunderstands the task).
3. **feedback**: send one concrete fix list (feedback template), re-arm the watcher, re-review once; second verdict can only be approve or reject.
4. **approve**/**reject**: present task, diff summary, verdict, and (if reject) recommended next step. **The user approves every merge**; never merge unprompted.
5. On approval: in the primary checkout, verify `git branch --show-current` prints the task's `<base>` (if not, stop and ask the user), then `git merge --no-ff fleet/<id>`. On conflict: `git merge --abort` immediately (never resolve conflicts yourself), then prompt the **same fleet-worker in its existing worktree** to `git rebase <base>` (no new task, worktree, or branch) or escalate to the user. No further merges until the primary checkout is clean.

Scouts: verify the report answers the brief, then relay your synthesis, not the raw file. That relay marks the scout `done`; tear it down immediately (tab + result file; no worktree or branch exists).

### 6. Teardown

After merge or explicit abandonment (confirm with the user if the branch has unmerged commits), set the terminal status, then:

```bash
"<skill-dir>/scripts/fleet-task.sh" teardown <id>   # --force-branch only for a user-confirmed abandonment
```

It closes the tab, removes the worktree and branch (refusing unmerged commits without `--force-branch`), and deletes the brief/result files. Never tear down unlanded work without explicit user approval.

## Context hygiene

- Fleet-workers get self-contained briefs, never conversation history or prior task results; chained tasks reference the merged code, not transcripts.
- You consume result files and targeted diffs; read pane output only on `blocked`/`unknown`/timeout/steer, capped at 120 lines. Never scroll-scrape a pane in place of the result file.
- Relay synthesis to the user in your own words with file:line references; never paste raw reports or full diffs.

## State files

| File | Purpose |
| --- | --- |
| `.fleet/active` | Enforcement flag; presence = fleet mode on |
| `.fleet/config.md` | Fleet-worker harness/model/effort (asked once, kept until the user changes it) |
| `.fleet/tasks.md` | Backlog + status table (source of truth across restarts) |
| `.fleet/<id>.result.md` | Fleet-worker's completion report (deleted at teardown) |
