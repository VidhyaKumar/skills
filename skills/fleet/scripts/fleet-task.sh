#!/bin/sh
# fleet-task.sh — deterministic task-row and worktree transitions for fleet mode.
#   create <id> <shape> <base>      provision worktree+branch (ship), append row;
#                                   prints resolved id (collisions auto-suffixed) and dir
#   status <id> <status>            set status, bump updated timestamp
#   pane <id> <pane-id>             record the fleet-worker's pane
#   teardown <id> [--force-branch]  close pane, remove worktree+branch, delete
#                                   brief/result files; row stays for off-prune
set -eu

root="$(git rev-parse --show-toplevel)"
fleet="$root/.fleet"
tasks="$fleet/tasks.md"

now() { date -u +%Y-%m-%dT%H:%MZ; }
die() { echo "fleet-task: $1" >&2; exit 1; }

# worktrees live outside every repo: ~/.fleet-worktrees/<project>-<hash>/<id>
# (hash disambiguates same-named projects at different paths; name deliberately
# distinct from the per-repo .fleet/ state dir)
wt_parent() {
  hash="$(printf %s "$root" | shasum | cut -c1-5)"
  echo "$HOME/.fleet-worktrees/$(basename "$root")-$hash"
}

have_id() {
  awk -F'|' -v id="$1" '/^\|/ { s=$2; gsub(/^[ \t]+|[ \t]+$/,"",s); if (s==id) found=1 } END { exit !found }' "$tasks"
}

field() { # id -> column N, trimmed
  awk -F'|' -v id="$1" -v col="$2" '/^\|/ { s=$2; gsub(/^[ \t]+|[ \t]+$/,"",s);
    if (s==id) { v=$col; gsub(/^[ \t]+|[ \t]+$/,"",v); print v; exit } }' "$tasks"
}

update_col() { # id column-index value; bumps updated (col 9)
  awk -F'|' -v OFS='|' -v id="$1" -v col="$2" -v val="$3" -v ts="$(now)" '
    /^\|/ { s=$2; gsub(/^[ \t]+|[ \t]+$/,"",s);
      if (s==id) { $col=" " val " "; $9=" " ts " " } }
    { print }' "$tasks" > "$tasks.tmp" && mv "$tasks.tmp" "$tasks"
}

[ -f "$tasks" ] || die "no $tasks — activate fleet first"

case "${1:-}" in
  create)
    id="${2:?id}"; shape="${3:?shape (ship|scout)}"; base="${4:?base branch}"
    kind="$(sed -n 's/^kind:[ 	]*//p' "$fleet/config.md" 2>/dev/null | head -1)"
    [ -n "$kind" ] || die "no kind in $fleet/config.md — write the fleet-worker config first"
    want="$id"; n=2
    while have_id "$id"; do id="$want-$n"; n=$((n+1)); done
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
    printf '| %s | %s | %s | queued | - | %s | %s | %s |\n' \
      "$id" "$shape" "$kind" "$branch" "$base" "$(now)" >> "$tasks"
    echo "id=$id"
    echo "dir=$dir"
    ;;
  status)
    id="${2:?id}"; st="${3:?status}"
    case "$st" in
      queued|dispatched|working|blocked|review|feedback|awaiting-approval|merged|abandoned|done) ;;
      *) die "unknown status '$st'" ;;
    esac
    have_id "$id" || die "no row for '$id'"
    update_col "$id" 5 "$st"
    echo "fleet-task: $id -> $st"
    ;;
  pane)
    id="${2:?id}"; p="${3:?pane id}"
    have_id "$id" || die "no row for '$id'"
    update_col "$id" 6 "$p"
    echo "fleet-task: $id pane $p"
    ;;
  teardown)
    id="${2:?id}"; force="${3:-}"
    have_id "$id" || die "no row for '$id'"
    shape="$(field "$id" 3)"; pane="$(field "$id" 6)"
    if [ "$pane" != "-" ] && [ -n "$pane" ]; then
      herdr pane close "$pane" >/dev/null 2>&1 \
        || echo "fleet-task: warn — pane $pane not closed (already gone?)" >&2
    fi
    if [ "$shape" = "ship" ]; then
      parent="$(wt_parent)"
      dir="$parent/$id"
      if [ -d "$dir" ]; then git -C "$root" worktree remove "$dir"; fi
      if [ "$force" = "--force-branch" ]; then
        git -C "$root" branch -D "fleet/$id"
      else
        # refuses unmerged commits; rerun with --force-branch after user confirms
        git -C "$root" branch -d "fleet/$id"
      fi
      rmdir "$parent" 2>/dev/null || true
    fi
    rm -f "$fleet/$id.brief.md" "$fleet/$id.result.md"
    echo "fleet-task: $id torn down"
    ;;
  *)
    echo "usage: fleet-task.sh create <id> <ship|scout> <base> | status <id> <status> | pane <id> <pane-id> | teardown <id> [--force-branch]" >&2
    exit 64
    ;;
esac
