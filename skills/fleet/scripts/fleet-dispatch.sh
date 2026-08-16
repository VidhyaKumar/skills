#!/bin/sh
# fleet-dispatch.sh <id> <pane-id> — one atomic dispatch: start the fleet-worker
# per .fleet/config.md, send its staged brief, arm the watcher, mark the row
# dispatched. Requires an existing row (fleet-task.sh create), the filled
# .fleet/<id>.brief.md, and HERDR_PANE_ID (the fleet-manager's own pane).
set -eu

id="${1:?task id}"
pane="${2:?fleet-worker pane id}"

root="$(git rev-parse --show-toplevel)"
fleet="$root/.fleet"
brief="$fleet/$id.brief.md"
sdir="$(cd "$(dirname "$0")" && pwd -P)"

die() { echo "fleet-dispatch: $1" >&2; exit 1; }

[ -f "$brief" ] || die "no $brief — stage the filled brief first"
[ -f "$fleet/config.md" ] || die "no $fleet/config.md — write the fleet-worker config first"
[ -n "${HERDR_PANE_ID:-}" ] || die "HERDR_PANE_ID not set — run from the fleet-manager's herdr pane"

cfg() { sed -n "s/^$1:[ 	]*//p" "$fleet/config.md" | head -1; }
kind="$(cfg kind)"; model="$(cfg model)"; effort="$(cfg effort)"; extra="$(cfg flags)"
[ -n "$kind" ] || die "kind missing in config.md"

case "$kind" in
  pi)     [ -n "$model" ] && [ -n "$effort" ] || die "pi needs model and effort in config.md"
          set -- --model "$model:$effort" ;;
  codex)  [ -n "$model" ] && [ -n "$effort" ] || die "codex needs model and effort in config.md"
          set -- -m "$model" -c "model_reasoning_effort=$effort" ;;
  grok)   [ -n "$model" ] && [ -n "$effort" ] || die "grok needs model and effort in config.md"
          set -- -m "$model" --reasoning-effort "$effort" ;;
  claude) [ -n "$model" ] || die "claude needs model in config.md"
          set -- --model "$model" ;;
  *)      [ -n "$model" ] && die "unknown kind '$kind': put its model/effort flags in 'flags:' instead of 'model:'"
          set -- ;;
esac

# $extra unquoted on purpose: 'flags:' is a whitespace-separated argument list
herdr agent start "fleet-$id" --kind "$kind" --pane "$pane" -- "$@" $extra
herdr agent prompt "fleet-$id" "$(cat "$brief")"
nohup bash "$sdir/fleet-watch.sh" "$id" "$HERDR_PANE_ID" >/dev/null 2>&1 &
sh "$sdir/fleet-task.sh" pane "$id" "$pane" >/dev/null
sh "$sdir/fleet-task.sh" status "$id" dispatched >/dev/null
echo "fleet-dispatch: $id -> $kind in pane $pane (brief sent, watcher armed)"
