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

herdr agent wait "fleet-$id" --timeout "$timeout" >/dev/null 2>&1
code=$?

status=""
if command -v jq >/dev/null 2>&1; then
  status="$(herdr agent get "fleet-$id" 2>/dev/null \
    | jq -r '.result.agent.agent_status // empty')" || status=""
fi
[ -n "$status" ] || status="gone-or-unreadable"

herdr agent prompt "$orch" "FLEET-EVENT $id: fleet-worker status '$status' (wait exit $code). Handle per Supervise: check the result file, triage blocked, or re-arm the watcher." >/dev/null 2>&1
