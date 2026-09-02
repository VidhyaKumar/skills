#!/usr/bin/env bash
# PreToolUse guard for fleet mode. Inert unless <repo-root>/.fleet/active exists.
# Blocks the fleet-manager's file mutations so task work goes to fleet-workers.
# Accepts Claude Code/Codex payloads (.tool_name/.tool_input, snake_case) and
# Grok Build payloads (.toolName/.toolInput, camelCase).
# Bash is checked against a read-only allowlist: every command in the pipeline
# must be one we know cannot write, and anything unrecognized is refused.
set -euo pipefail

input="$(cat)"
sdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

if command -v jq >/dev/null 2>&1; then
  cwd="$(jq -r '.cwd // empty' <<<"$input")"
else
  # No jq: fall back to the hook's own cwd so an armed repo still fails loud.
  cwd="$PWD"
fi
# Same fallback when jq is present but the payload omits .cwd: exiting 0 here
# would silently disarm the guard.
[ -n "$cwd" ] || cwd="$PWD"
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

# Only .fleet/ is writable. Deliberately a glob, not a prefix match against
# $root: on macOS the payload cwd (/tmp/x) and git's toplevel (/private/tmp/x)
# differ, so anchoring to $root denies every legitimate .fleet/ write. '..' is
# refused outright rather than normalized, which closes the traversal path.
exempt() {
  case "$1" in
    *..*) return 1 ;;
    .fleet/*|*/.fleet/*) return 0 ;;
    *) return 1 ;;
  esac
}

# Only the skill's own fleet-*.sh scripts may run: an allowed redirect can
# write a script into /tmp or .fleet/, so "any named script" is a write path.
fleet_script() {
  case "${1##*/}" in fleet-*.sh) ;; *) return 1 ;; esac
  [ "$(cd "$cwd" 2>/dev/null && cd "$(dirname "$1")" 2>/dev/null && pwd -P)" = "$sdir" ]
}

case "$tool" in
  Edit|Write|NotebookEdit|search_replace|apply_patch)
    file_path="$(jq -r '(.tool_input // .toolInput // {})
      | (.file_path // .notebook_path // .filePath // .path // empty)' <<<"$input")"
    if [ -n "$file_path" ]; then
      exempt "$file_path" && exit 0
      deny "direct file edits are blocked ($tool on $file_path)."
    else
      # Pathless apply_patch: parse every *** Add/Update/Delete File: path
      # and every Codex *** Move to: destination. Allow only when at least
      # one path exists and every path is under .fleet/. Fail closed if no
      # paths can be established.
      patch="$(jq -r '
        (.tool_input // .toolInput // {})
        | if type == "string" then .
          else (.input // .patch // .diff // empty)
          end
      ' <<<"$input")"
      paths="$(printf '%s\n' "$patch" | sed -nE 's/^[*][*][*] (Add File|Update File|Delete File|Move to):[[:space:]]+//p')"
      found=0
      while IFS= read -r p; do
        p="${p%"${p##*[![:space:]]}"}"
        [ -n "$p" ] || continue
        found=1
        exempt "$p" || deny "direct file edits are blocked ($tool on $p)."
      done < <(printf '%s\n' "$paths")
      [ "$found" -eq 1 ] || deny "direct file edits are blocked ($tool)."
      exit 0
    fi
    ;;
  Bash|run_terminal_command)
    cmd="$(jq -r '(.tool_input // .toolInput // {}) | .command // empty' <<<"$input")"
    # Three views of the command, each for a different question.
    # 1. unq: quotes removed only where they wrap a redirect target, so
    #    `> ".fleet/x"` yields a real path while `--format='%h > %s'` is
    #    untouched (its '>' is inside the quotes, not before them).
    unq="$(sed -E 's/(>>?)[[:space:]]*"([^"]*)"/\1 \2/g; s/(>>?)[[:space:]]*'"'"'([^'"'"']*)'"'"'/\1 \2/g' <<<"$cmd")"
    # 2. stripped: remaining quoted text becomes a placeholder so quoted '>'
    #    can't fake a redirection. A placeholder, not deletion: `echo x >
    #    "file"` must still look like one.
    stripped="$(sed -E "s/'[^']*'/Q/g; s/\"[^\"]*\"/Q/g" <<<"$unq")"
    # 3. bare: used only to find the head of each segment, so a quoted command
    #    name survives ("<skill-dir>/scripts/fleet-task.sh" is how SKILL.md
    #    invokes it) and a split-up one ("r"m) still resolves to the name it
    #    will run. Quoted spans holding a shell metacharacter collapse to Q
    #    first — deleting those quotes would turn `cut -d"|"` into a real pipe
    #    — and only then are the remaining quote characters dropped.
    bare="$(sed -E 's/"[^"]*[;|&$`][^"]*"/Q/g; s/'"'"'[^'"'"']*[;|&$`][^'"'"']*'"'"'/Q/g' <<<"$cmd" \
            | tr -d "'\"")"

    # Allowlist, not blocklist. A blocklist of shell verbs cannot be made
    # sound — /bin/rm, \rm, `echo ... | bash`, `python -c"..."` and a long
    # tail of equivalents all reach the same write. So: every command in the
    # pipeline must be one we know is read-only, and anything unrecognized is
    # refused. Widening this list is a deliberate act; guessing is not.
    # awk/sed/yq are absent on purpose: awk has system() and `print > file`,
    # sed has `w file`, yq has -i. They are interpreters that can write, same
    # class as the perl/python we already refuse. less/more shell out via `!`.
    ALLOW="cat head tail ls tree find grep rg egrep fgrep wc sort uniq cut tr
jq diff comm join column basename dirname realpath readlink stat file du df ps
echo printf pwd date test true false which type herdr git sleep"

    # Command substitution and eval hide a verb from the head-of-segment check.
    if grep -qE '\$\(|`' <<<"$stripped"; then
      deny "command substitution blocked (it hides the command being run)."
    fi
    # In-place editors and tee are writes even though their names look benign.
    if grep -qE "(^|[;&|[:space:]'\"])(sed[[:space:]]+(-[a-zA-Z]*i|--in-place)|perl[[:space:]]+(-[a-zA-Z]*i|--in-place)|tee[[:space:]])" <<<"$stripped"; then
      deny "mutating shell command blocked (in-place edit/tee)."
    fi
    # find and sort are read-only tools with write actions bolted on.
    if grep -qE "(^|[;&|[:space:]'\"])find[[:space:]]" <<<"$stripped" \
      && grep -qE "[[:space:]]-(delete|exec|execdir|ok|okdir|fprint|fprintf|fls)([[:space:]]|$)" <<<"$stripped"; then
      deny "find action that writes or runs a command blocked."
    fi
    if grep -qE "(^|[;&|[:space:]'\"])sort[[:space:]]" <<<"$stripped" \
      && grep -qE "[[:space:]](-o|--output)([[:space:]]|=)" <<<"$stripped"; then
      deny "sort writing to a file blocked."
    fi

    # Split the pipeline on ; && || | & and check the head of each segment.
    while IFS= read -r seg; do
      # shellcheck disable=SC2086 # deliberate word splitting into tokens
      set -- $seg
      # skip VAR=val prefixes and transparent wrappers
      while [ "$#" -gt 0 ]; do
        case "$1" in
          *=*) shift ;;
          nohup|timeout|time|builtin|command|env) shift ;;
          *) break ;;
        esac
      done
      [ "$#" -gt 0 ] || continue
      base="${1##*/}"
      case "$base" in
        fleet-*.sh) fleet_script "$1" || deny "only the fleet scripts in $sdir may be run ($1)."; continue ;;
        bash|sh|zsh|dash|ksh)
          # Running a named script is fine. -c smuggles a command inline, and
          # a shell with no script argument reads one from stdin, which is how
          # `echo "rm -rf src" | bash` gets there.
          shellname="$base"; shift; script=""
          while [ "$#" -gt 0 ]; do
            case "$1" in
              -c*|--command*) deny "shell -c blocked." ;;
              -s*) deny "$shellname reading a script from stdin blocked." ;;
              -*) ;;
              *) script="$1"; break ;;
            esac
            shift
          done
          [ -n "$script" ] || deny "$shellname with no script argument reads from stdin; blocked."
          fleet_script "$script" || deny "$shellname may only run the fleet scripts in $sdir ($script)."
          continue ;;
        git)
          # git is dual-use: allow only the read-only side, plus the merge the
          # fleet-manager performs itself. --git-dir/--work-tree/-c are refused
          # because they re-point git at another tree or rewrite its config.
          if ! grep -qE "(^|[[:space:]])git[[:space:]]+(--no-pager[[:space:]]+|-C[[:space:]]+[^[:space:]-][^[:space:]]*[[:space:]]+)*(diff|log|status|show|rev-parse|rev-list|merge-base|ls-files|ls-tree|cat-file|blame|describe|shortlog|symbolic-ref|for-each-ref|branch|worktree|merge)([[:space:]]|\$)" <<<"$seg"; then
            deny "git subcommand not on the fleet allowlist ($seg)."
          fi
          # Options are checked per token after the subcommand, so `--merged`
          # (which contains "-m") and paths containing "add" are not mistaken
          # for mutations.
          shift
          while [ "$#" -gt 0 ]; do
            case "$1" in --no-pager) shift ;; -C) shift 2 ;; *) break ;; esac
          done
          sub="${1:-}"
          [ "$#" -gt 0 ] && shift
          for a in "$@"; do
            case "$sub:$a" in
              branch:-[cCdDfmMu]*|branch:--copy|branch:--delete|branch:--move|branch:--force|branch:--set-upstream*|branch:--unset-upstream|branch:--edit-description)
                deny "mutating git branch blocked." ;;
              worktree:list|worktree:-*) ;;
              worktree:*) deny "mutating git worktree blocked (use fleet-task.sh)." ;;
            esac
          done
          continue ;;
        *)
          # ALLOW spans several lines; flatten it or a word at a line edge is
          # bounded by a newline instead of a space and never matches.
          case " $(tr '\n' ' ' <<<"$ALLOW") " in
            *" $base "*) continue ;;
            *) deny "'$base' is not on the fleet read-only allowlist. If this is genuinely read-only, ask the user to widen the list; otherwise dispatch a fleet-worker." ;;
          esac ;;
      esac
      # Neutralise fd duplication (2>&1, >&2, &>log) before splitting, so its
      # '&' is not mistaken for a background separator.
    done < <(sed -E 's/[0-9]*>&[0-9-]+/RD/g; s/&>>?/RD/g' <<<"$bare" \
             | sed -E 's/(\|\||&&|[;|&])/\n/g')

    # An allowlisted command can still write through a redirect.
    while IFS= read -r t; do
      [ -n "$t" ] || continue
      [ "$t" = /dev/null ] && continue
      case "$t" in /tmp/*) continue ;; esac
      exempt "$t" || deny "shell redirection into a file blocked ($t)."
    done < <(grep -oE '>>?[[:space:]]*[^&|;[:space:]]+' <<<"$stripped" | sed -E 's/^>>?[[:space:]]*//')
    exit 0
    ;;
  *) exit 0 ;;
esac
