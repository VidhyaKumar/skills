#!/bin/sh
# fleet-dispatch.sh <id> — one atomic dispatch: open a tab in the task's dir,
# start the fleet-worker per .fleet/config.md, send its staged brief, arm the
# watcher, mark the row dispatched. Requires an existing row (fleet-task.sh
# create), the filled .fleet/<id>.brief.md, and HERDR_PANE_ID (the
# fleet-manager's own pane).
set -eu

id="${1:?task id}"

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
  pi|codex|grok|claude) [ -n "$model" ] && [ -n "$effort" ] || die "$kind needs model and effort in config.md" ;;
  *) [ -z "$model" ] || die "unknown kind '$kind': put its model/effort flags in 'flags:' instead of 'model:'" ;;
esac
case "$kind" in
  pi)     set -- --model "$model:$effort" ;;
  codex)  set -- -m "$model" -c "model_reasoning_effort=$effort" ;;
  grok)   set -- -m "$model" --reasoning-effort "$effort" ;;
  claude) set -- --model "$model" --effort "$effort" ;;
  *)      set -- ;;
esac

name="fw-$id"
dir="$(sh "$sdir/fleet-task.sh" dir "$id")"
created="$(herdr tab create --cwd "$dir" --label "$name" --no-focus)"
tab="$(printf %s "$created" | jq -r '.result.tab.tab_id // empty')"
pane="$(printf %s "$created" | jq -r '.result.root_pane.pane_id // empty')"
[ -n "$tab" ] && [ -n "$pane" ] || die "tab create failed: $created"

# The fresh tab's shell needs a moment to reach its interactive prompt;
# herdr rejects agent start until then (agent_pane_busy), so retry ~10s.
# On permanent failure, close the tab we just opened before dying.
tries=0
# $extra unquoted on purpose: 'flags:' is a whitespace-separated argument list
until out="$(herdr agent start "$name" --kind "$kind" --pane "$pane" -- "$@" $extra 2>&1)"; do
  tries=$((tries + 1))
  if [ "$tries" -ge 10 ] || ! printf %s "$out" | grep -q agent_pane_busy; then
    herdr tab close "$tab" >/dev/null 2>&1 || true
    die "agent start failed: $out"
  fi
  sleep 1
done
# A failed prompt leaves a started agent with no brief; close the tab we opened
# rather than stranding it (set -e would otherwise abort with the tab live).
herdr agent prompt "$name" "$(cat "$brief")" || {
  herdr tab close "$tab" >/dev/null 2>&1 || true
  die "agent prompt failed — tab $tab closed, row left queued"
}
sh "$sdir/fleet-task.sh" watch "$id" >/dev/null
sh "$sdir/fleet-task.sh" tab "$id" "$tab" >/dev/null
sh "$sdir/fleet-task.sh" status "$id" dispatched >/dev/null
echo "fleet-dispatch: $id -> $kind in tab $tab (brief sent, watcher armed)"
