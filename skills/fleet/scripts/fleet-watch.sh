#!/usr/bin/env bash
# Detached per-task watcher for fleet mode. Waits for one fleet-worker event, then
# wakes the fleet-manager by prompting its pane. One-shot by design: the
# fleet-manager re-arms it after handling each event, so supervision stays
# event-driven in any harness (no polling, no harness background tasks).
# Usage: fleet-watch.sh <task-id> <fleet-manager-pane-id> [timeout-ms]
set -u

id="${1:?task id required}"
orch="${2:?fleet-manager pane id required}"
timeout="${3:-900000}"

agent="fw-$id"

# Two-phase wait: the dispatch prompt may not have flipped the fleet-worker to
# 'working' yet, and a settled-state wait on a still-idle agent returns
# immediately — a premature event. Wait for 'working' first (worker already
# past it -> instant; worker already finished -> 15s, then settle correctly).
herdr agent wait "$agent" --until working --timeout 15000 >/dev/null 2>&1
herdr agent wait "$agent" --timeout "$timeout" >/dev/null 2>&1
code=$?

status=""
if command -v jq >/dev/null 2>&1; then
  status="$(herdr agent get "$agent" 2>/dev/null \
    | jq -r '.result.agent.agent_status // empty')" || status=""
fi
[ -n "$status" ] || status="gone-or-unreadable"

msg="FLEET-EVENT $id: fleet-worker status '$status' (wait exit $code). Handle per Supervise: check the result file, triage blocked, or re-arm the watcher."
tries=0
max=3
last=""
while [ "$tries" -lt "$max" ]; do
  tries=$((tries + 1))
  if last="$(herdr agent prompt "$orch" "$msg" 2>&1)"; then
    exit 0
  fi
  [ "$tries" -lt "$max" ] && sleep 1
done
echo "fleet-watch: failed to deliver manager event for $id after $max attempts: ${last:-herdr agent prompt failed}" >&2
exit 1
