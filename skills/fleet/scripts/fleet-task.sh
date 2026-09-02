#!/bin/sh
# fleet-task.sh — every deterministic fleet transition, in one script.
#   on | off                        arm / disarm fleet mode (off stops watchers)
#   create <id> <shape> <base>      provision worktree+branch (ship), append row;
#                                   prints resolved id (collisions auto-suffixed) and dir
#   status <id> <status>            set status, bump updated timestamp
#   tab <id> <tab-id>               record the fleet-worker's tab
#   dir <id>                        print the task's working dir (worktree or root)
#   watch <id> [timeout-ms]         (re)arm the detached watcher, record its pid
#   teardown <id> [--force-branch]  remove worktree+branch, close tab, delete
#                                   brief/result files and the row
# A row exists exactly while its task is live; teardown is the terminal event.
set -eu

root="$(git rev-parse --show-toplevel)"
fleet="$root/.fleet"
tasks="$fleet/tasks.md"
sdir="$(cd "$(dirname "$0")" && pwd -P)"
# OS lock: lockf (macOS) or flock (Linux), 30s timeout. File contents are not
# ownership — OS lock state is authoritative. Mutating commands re-exec once
# under FLEET_TASKS_LOCKED.
tasks_lock="$fleet/tasks.lock"

now() { date -u +%Y-%m-%dT%H:%MZ; }
die() { echo "fleet-task: $1" >&2; exit 1; }

with_tasks_lock() {
  if [ -n "${FLEET_TASKS_LOCKED:-}" ]; then
    return 0
  fi
  if command -v lockf >/dev/null 2>&1; then
    FLEET_TASKS_LOCKED=1 exec lockf -k -t 30 "$tasks_lock" "$0" "$@"
  elif command -v flock >/dev/null 2>&1; then
    FLEET_TASKS_LOCKED=1 exec flock -w 30 "$tasks_lock" "$0" "$@"
  else
    die "neither lockf nor flock is available; cannot lock $tasks"
  fi
}

# worktrees live outside every repo: ~/.fleet-worktrees/<project>-<hash>/<id>
# (hash disambiguates same-named projects at different paths; name deliberately
# distinct from the per-repo .fleet/ state dir)
wt_parent() {
  hash="$(printf %s "$root" | shasum | cut -c1-5)"
  echo "$HOME/.fleet-worktrees/$(basename "$root")-$hash"
}

# Watchers are detached background processes; kill one before its task's agent
# disappears, or it fires a phantom FLEET-EVENT at the fleet-manager.
# A pidfile outlives the watcher that exits on its own, so the pid may have
# been recycled by then — confirm it is still a fleet-watch before killing.
stop_watcher() {
  pidfile="$fleet/$1.watch.pid"
  [ -f "$pidfile" ] || return 0
  pid="$(cat "$pidfile")"
  case "$pid" in
    ''|*[!0-9]*) ;;
    *) if ps -p "$pid" -o command= 2>/dev/null | grep -q fleet-watch; then
         kill "$pid" 2>/dev/null || true
       fi ;;
  esac
  rm -f "$pidfile"
}

task_rows() {
  [ -f "$tasks" ] || { echo 0; return; }
  awk -F'|' '/^\|/ { n++; if (n > 2) rows++ } END { print rows + 0 }' "$tasks"
}

# columns: 2 id, 3 shape, 4 status, 5 tab, 6 branch, 7 base, 8 updated
field() { # id column-index -> trimmed value ("" when no row)
  awk -F'|' -v id="$1" -v col="$2" '/^\|/ { s=$2; gsub(/^[ \t]+|[ \t]+$/,"",s);
    if (s==id) { v=$col; gsub(/^[ \t]+|[ \t]+$/,"",v); print v; exit } }' "$tasks"
}

have_id() { [ -n "$(field "$1" 2)" ]; }

update_col() { # id column-index value; bumps updated (col 8)
  awk -F'|' -v OFS='|' -v id="$1" -v col="$2" -v val="$3" -v ts="$(now)" '
    /^\|/ { s=$2; gsub(/^[ \t]+|[ \t]+$/,"",s);
      if (s==id) { $col=" " val " "; $8=" " ts " " } }
    { print }' "$tasks" > "$tasks.tmp" && mv "$tasks.tmp" "$tasks"
}

delete_row() {
  awk -F'|' -v id="$1" '/^\|/ { s=$2; gsub(/^[ \t]+|[ \t]+$/,"",s); if (s==id) next } { print }' \
    "$tasks" > "$tasks.tmp" && mv "$tasks.tmp" "$tasks"
}

case "${1:-}" in
  on|off) ;;
  *) [ -f "$tasks" ] || die "no $tasks — run fleet-task.sh on first" ;;
esac

case "${1:-}" in
  on)
    [ "${HERDR_ENV:-}" = 1 ] || die "fleet mode needs a running herdr session (HERDR_ENV=1)"
    # The guard and watcher both parse JSON with jq; without it enforcement
    # would silently vanish, so refuse to arm at all.
    command -v jq >/dev/null 2>&1 || die "jq is required (guard/watcher depend on it) — install jq first"
    if ! command -v lockf >/dev/null 2>&1 && ! command -v flock >/dev/null 2>&1; then
      die "neither lockf nor flock is available; parallel-safe task state requires one of them"
    fi
    # gitignore before arming: once .fleet/active exists the guard blocks this edit
    grep -qx '\.fleet/' "$root/.gitignore" 2>/dev/null || printf '\n.fleet/\n' >> "$root/.gitignore"
    mkdir -p "$fleet"
    if [ ! -f "$tasks" ]; then
      printf '| id | shape | status | tab | branch | base | updated |\n| --- | --- | --- | --- | --- | --- | --- |\n' > "$tasks"
    fi
    touch "$fleet/active"
    # role-based names: fleet-manager tab/agent = fm-<project> (fleet-workers
    # get fw-<id> at dispatch)
    if [ -n "${HERDR_PANE_ID:-}" ]; then
      tab="$(herdr pane list 2>/dev/null | jq -r --arg p "$HERDR_PANE_ID" \
        '.result.panes[] | select(.pane_id==$p) | .tab_id' 2>/dev/null)" || tab=""
      if [ -n "$tab" ]; then herdr tab rename "$tab" "fm-$(basename "$root")" >/dev/null 2>&1 || true; fi
      herdr agent rename "$HERDR_PANE_ID" "fm-$(basename "$root")" >/dev/null 2>&1 || true
    fi
    hook_warn=""
    grep -qs 'fleet-guard' "$HOME/.claude/settings.json" "$HOME/.codex/hooks.json" "$HOME"/.grok/hooks/*.json "$HOME"/.pi/agent/extensions/*.ts 2>/dev/null \
      || hook_warn=" — WARNING: no harness hook/extension config references fleet-guard; enforcement is instruction-only"
    routing=""
    [ -f "$fleet/config.md" ] || routing=", no fleet-worker config — ask the user (default: match fleet-manager)"
    echo "fleet: on ($(task_rows) live task rows — reconcile if > 0$routing)$hook_warn"
    ;;
  off)
    rm -f "$fleet/active"
    for pidfile in "$fleet"/*.watch.pid; do
      [ -f "$pidfile" ] || continue
      stop_watcher "$(basename "$pidfile" .watch.pid)"
    done
    echo "fleet: off ($(task_rows) live task rows kept)"
    ;;
  create)
    id="${2:?id}"; shape="${3:?shape (ship|scout)}"; base="${4:?base branch}"
    # The id becomes herdr agent/tab name fw-<id>: herdr caps names at 32
    # chars ([a-z][a-z0-9_-]{0,31}), so ids are [a-z0-9_-] and <= 29 chars.
    # LC_ALL=C: bare a-z ranges are collation-dependent and can admit uppercase
    printf %s "$id" | LC_ALL=C grep -qE '^[a-z0-9_-]+$' \
      || die "invalid id '$id': lowercase letters, digits, '-' or '_' only"
    with_tasks_lock "$@"
    want="$id"; n=2
    while have_id "$id"; do id="$want-$n"; n=$((n+1)); done
    [ "${#id}" -le 29 ] || die "id '$id' too long: fw-$id exceeds herdr's 32-char agent-name limit (ids max 29 chars)"
    case "$shape" in
      ship)
        dir="$(wt_parent)/$id"
        mkdir -p "$(wt_parent)"
        git -C "$root" worktree add "$dir" -b "fleet/$id" "$base" >/dev/null
        dir="$(cd "$dir" && pwd -P)"
        branch="fleet/$id"
        ;;
      scout) dir="$root"; branch="-" ;;
      *) die "shape must be ship or scout" ;;
    esac
    printf '| %s | %s | queued | - | %s | %s | %s |\n' \
      "$id" "$shape" "$branch" "$base" "$(now)" >> "$tasks"
    echo "id=$id"
    echo "dir=$dir"
    ;;
  status)
    id="${2:?id}"; st="${3:?status}"
    case "$st" in
      queued|dispatched|working|blocked|review|feedback|awaiting-approval) ;;
      *) die "unknown status '$st'" ;;
    esac
    with_tasks_lock "$@"
    have_id "$id" || die "no row for '$id'"
    update_col "$id" 4 "$st"
    echo "fleet-task: $id -> $st"
    ;;
  tab)
    id="${2:?id}"; t="${3:?tab id}"
    # the row is a '|'-delimited table: a '|' in the value would corrupt it
    printf %s "$t" | LC_ALL=C grep -qE '^[A-Za-z0-9_:.-]+$' \
      || die "invalid tab id '$t'"
    with_tasks_lock "$@"
    have_id "$id" || die "no row for '$id'"
    update_col "$id" 5 "$t"
    echo "fleet-task: $id tab $t"
    ;;
  dir)
    id="${2:?id}"
    have_id "$id" || die "no row for '$id'"
    if [ "$(field "$id" 3)" = "ship" ]; then
      d="$(wt_parent)/$id"
      [ -d "$d" ] || die "worktree $d missing — was it created?"
      echo "$d"
    else
      echo "$root"
    fi
    ;;
  watch)
    id="${2:?id}"
    [ -n "${HERDR_PANE_ID:-}" ] || die "HERDR_PANE_ID not set — run from the fleet-manager's herdr pane"
    have_id "$id" || die "no row for '$id'"
    # one watcher per task: a second live one would fire a duplicate event
    stop_watcher "$id"
    nohup bash "$sdir/fleet-watch.sh" "$id" "$HERDR_PANE_ID" ${3:+"$3"} >/dev/null 2>&1 &
    echo $! > "$fleet/$id.watch.pid"
    echo "fleet-task: $id watcher armed (pid $!)"
    ;;
  teardown)
    id="${2:?id}"; force="${3:-}"
    case "$force" in ""|--force-branch) ;; *) die "unknown option '$force'" ;; esac
    with_tasks_lock "$@"
    have_id "$id" || die "no row for '$id'"
    shape="$(field "$id" 3)"; tab="$(field "$id" 5)"
    if [ "$shape" = "ship" ]; then
      dir="$(wt_parent)/$id"
      # git's own refusals come first, before anything is destroyed:
      # `git worktree remove` refuses a dirty tree, and `git branch -d` would
      # refuse unmerged commits only after the worktree is gone — so that one
      # is checked up front. A refusal leaves the task intact for a rerun.
      if [ "$force" != "--force-branch" ] \
        && git -C "$root" rev-parse --verify -q "refs/heads/fleet/$id" >/dev/null; then
        git -C "$root" merge-base --is-ancestor "fleet/$id" "$(field "$id" 7)" 2>/dev/null \
          || die "fleet/$id has unmerged commits — rerun with --force-branch after the user confirms"
      fi
      if [ -d "$dir" ]; then
        git -C "$root" worktree remove ${force:+--force} "$dir"
      fi
      del=-d; [ -n "$force" ] && del=-D
      if git -C "$root" rev-parse --verify -q "refs/heads/fleet/$id" >/dev/null; then
        git -C "$root" branch "$del" "fleet/$id"
      fi
      rmdir "$(wt_parent)" 2>/dev/null || true
    fi
    stop_watcher "$id"
    if [ "$tab" != "-" ] && [ -n "$tab" ]; then
      herdr tab close "$tab" >/dev/null 2>&1 \
        || echo "fleet-task: warn — tab $tab not closed (already gone?)" >&2
    fi
    rm -f "$fleet/$id.brief.md" "$fleet/$id.result.md"
    delete_row "$id"
    echo "fleet-task: $id torn down"
    ;;
  *)
    echo "usage: fleet-task.sh on | off | create <id> <ship|scout> <base> | status <id> <status> | tab <id> <tab-id> | dir <id> | watch <id> [timeout-ms] | teardown <id> [--force-branch]" >&2
    exit 64
    ;;
esac
