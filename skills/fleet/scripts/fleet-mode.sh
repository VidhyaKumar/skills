#!/bin/sh
# fleet-mode.sh on|off — deterministic fleet state transitions.
# Run from anywhere inside the target repo. Prints one state line for the
# orchestrator to relay. Never removes .fleet/ (fast repeat activation keys on it).
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
    # gitignore before arming: once .fleet/active exists the guard blocks this edit
    grep -qx '\.fleet/' "$root/.gitignore" 2>/dev/null || printf '\n.fleet/\n' >> "$root/.gitignore"
    mkdir -p "$fleet"
    if [ ! -f "$tasks" ]; then
      printf '| id | shape | type | worker | status | pane | branch | base | updated |\n| --- | --- | --- | --- | --- | --- | --- | --- | --- |\n' > "$tasks"
    fi
    touch "$fleet/active"
    echo "fleet: on ($(task_rows) existing task rows — reconcile if > 0)"
    ;;
  off)
    rm -f "$fleet/active"
    if [ -f "$tasks" ]; then
      awk -F'|' '
        !/^\|/ { print; next }
        { n++ }
        n <= 2 { print; next }
        { s = $6; gsub(/^[ \t]+|[ \t]+$/, "", s);
          if (s != "merged" && s != "abandoned" && s != "done") print }
      ' "$tasks" > "$tasks.tmp" && mv "$tasks.tmp" "$tasks"
    fi
    echo "fleet: off ($(task_rows) unfinished rows kept)"
    ;;
  uninstall)
    if [ -f "$fleet/active" ]; then
      echo "fleet: still active — run 'fleet-mode.sh off' first" >&2
      exit 1
    fi
    if [ "$(task_rows)" -gt 0 ]; then
      echo "fleet: $(task_rows) unfinished task rows in $tasks — resolve or abandon them first" >&2
      exit 1
    fi
    rm -rf "$fleet"
    if [ -f "$root/.gitignore" ]; then
      grep -vx '\.fleet/' "$root/.gitignore" > "$root/.gitignore.tmp" && mv "$root/.gitignore.tmp" "$root/.gitignore"
    fi
    echo "fleet: uninstalled (.fleet/ removed, gitignore entry dropped; harness hook entry left in place)"
    ;;
  *)
    echo "usage: fleet-mode.sh on|off|uninstall" >&2
    exit 64
    ;;
esac
