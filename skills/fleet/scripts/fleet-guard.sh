#!/usr/bin/env bash
# PreToolUse guard for fleet mode. Inert unless <repo-root>/.fleet/active exists.
# Blocks the fleet-manager's file mutations so task work goes to fleet-workers.
# Accepts Claude Code/Codex payloads (.tool_name/.tool_input, snake_case) and
# Grok Build payloads (.toolName/.toolInput, camelCase).
# Bash blocking is heuristic: it catches common write patterns, not all of them.
set -euo pipefail

input="$(cat)"

if command -v jq >/dev/null 2>&1; then
  cwd="$(jq -r '.cwd // empty' <<<"$input")"
else
  # No jq: fall back to the hook's own cwd so an armed repo still fails loud.
  cwd="$PWD"
fi
[ -n "$cwd" ] || exit 0
root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" || root="$cwd"
[ -f "$root/.fleet/active" ] || exit 0

if ! command -v jq >/dev/null 2>&1; then
  echo "fleet mode active but jq is missing — the guard cannot inspect tool calls. Install jq, or have the user say 'fleet off'." >&2
  exit 2
fi

tool="$(jq -r '.tool_name // .toolName // empty' <<<"$input")"

deny() {
  echo "fleet mode active in $root: $1 Dispatch a fleet-worker instead (run /fleet to resume orchestrating). Only the user can deactivate (by saying 'fleet off')." >&2
  exit 2
}

case "$tool" in
  Edit|Write|NotebookEdit|search_replace|apply_patch)
    file_path="$(jq -r '(.tool_input // .toolInput // {})
      | (.file_path // .notebook_path // .filePath // .path // empty)' <<<"$input")"
    if [ -n "$file_path" ]; then
      case "$file_path" in
        *..*) deny "direct file edits are blocked ($tool on $file_path)." ;;
        .fleet/*|*/.fleet/*) exit 0 ;;
        *) deny "direct file edits are blocked ($tool on $file_path)." ;;
      esac
    else
      # Patch-body payloads (codex apply_patch) carry no path field; allow
      # only if the body references .fleet/ at all. Heuristic, fail-open.
      raw="$(jq -r '(.tool_input // .toolInput // {}) | tostring' <<<"$input")"
      case "$raw" in
        *.fleet/*) exit 0 ;;
        *) deny "direct file edits are blocked ($tool)." ;;
      esac
    fi
    ;;
  Bash|run_terminal_command)
    cmd="$(jq -r '(.tool_input // .toolInput // {}) | .command // empty' <<<"$input")"
    # In-place editors and tee are always writes.
    if grep -qE '(^|[;&|[:space:]])(sed[[:space:]]+-[a-zA-Z]*i|perl[[:space:]]+-[a-zA-Z]*i|tee[[:space:]])' <<<"$cmd"; then
      deny "mutating shell command blocked (in-place edit/tee)."
    fi
    # Redirection into files, unless the target is .fleet/, /tmp, or /dev/null.
    if grep -qE '>>?[[:space:]]*[^&|[:space:]]' <<<"$cmd" \
      && ! grep -qE '>>?[[:space:]]*("?[^[:space:]"]*\.fleet/|/tmp/|/dev/null)' <<<"$cmd"; then
      deny "shell redirection into a file blocked."
    fi
    exit 0
    ;;
  *) exit 0 ;;
esac
