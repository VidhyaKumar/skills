#!/bin/sh
# fleet-mode.sh on|off — deterministic fleet state transitions.
# Run from anywhere inside the target repo. Prints one state line for the
# fleet-manager to relay. Never removes .fleet/ (fast repeat activation keys on it).
set -eu

root="$(git rev-parse --show-toplevel)"
fleet="$root/.fleet"
tasks="$fleet/tasks.md"

task_rows() {
  [ -f "$tasks" ] || { echo 0; return; }
  awk -F'|' '/^\|/ { n++; if (n > 2) rows++ } END { print rows + 0 }' "$tasks"
}

case "${1:-}" in
  on)
    # The guard and watcher both parse JSON with jq; without it enforcement
    # would silently vanish, so refuse to arm at all.
    command -v jq >/dev/null 2>&1 || { echo "fleet: jq is required (guard/watcher depend on it) — install jq first" >&2; exit 1; }
    # gitignore before arming: once .fleet/active exists the guard blocks this edit
    grep -qx '\.fleet/' "$root/.gitignore" 2>/dev/null || printf '\n.fleet/\n' >> "$root/.gitignore"
    mkdir -p "$fleet"
    if [ ! -f "$tasks" ]; then
      printf '| id | shape | fleet-worker | status | tab | branch | base | updated |\n| --- | --- | --- | --- | --- | --- | --- | --- |\n' > "$tasks"
    fi
    touch "$fleet/active"
    # role-based names: fleet-manager tab/agent = fm-<project> (fleet-workers
    # get fw-<project>-<id> at dispatch)
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
    echo "fleet: on ($(task_rows) existing task rows — reconcile if > 0$routing)$hook_warn"
    ;;
  off)
    rm -f "$fleet/active"
    if [ -f "$tasks" ]; then
      awk -F'|' '
        !/^\|/ { print; next }
        { n++ }
        n <= 2 { print; next }
        { s = $5; gsub(/^[ \t]+|[ \t]+$/, "", s);
          if (s != "merged" && s != "abandoned" && s != "done") print }
      ' "$tasks" > "$tasks.tmp" && mv "$tasks.tmp" "$tasks"
    fi
    echo "fleet: off ($(task_rows) unfinished rows kept)"
    ;;
  uninstall)
    if [ -f "$fleet/active" ]; then "$0" off; fi
    if [ "$(task_rows)" -gt 0 ]; then
      echo "fleet: $(task_rows) unfinished task rows in $tasks — resolve or abandon them first:" >&2
      awk -F'|' '/^\|/ { n++; if (n > 2) { s = $2; gsub(/^[ \t]+|[ \t]+$/, "", s); print "  " s } }' "$tasks" >&2
      exit 1
    fi
    rm -rf "$fleet"
    echo "fleet: uninstalled (.fleet/ removed; gitignore entry and harness hook entry left in place)"
    ;;
  *)
    echo "usage: fleet-mode.sh on|off|uninstall" >&2
    exit 64
    ;;
esac
