# Shared fixtures for fleet public-seam tests. Sourced by run.sh.
# shellcheck shell=sh disable=SC2034

# $0 is the caller (run.sh). After a relative-path invocation plus cd,
# dirname "$0" is still relative to the original cwd and points nowhere.
# run.sh cds into tests/fleet/ before sourcing, so resolve scripts from there.
scripts_dir="$(CDPATH='' cd -- "../../skills/fleet/scripts" && pwd -P)" || {
  echo "helpers: cannot resolve ../../skills/fleet/scripts from $(pwd)" >&2
  exit 1
}
task_sh="$scripts_dir/fleet-task.sh"
guard_sh="$scripts_dir/fleet-guard.sh"
dispatch_sh="$scripts_dir/fleet-dispatch.sh"
watch_sh="$scripts_dir/fleet-watch.sh"

tmp_root=""
repo_n=0
fail_count=0
pass_count=0

die() { echo "helpers: $1" >&2; exit 1; }

cleanup() {
  if [ -n "${tmp_root:-}" ] && [ -d "$tmp_root" ]; then
    rm -rf "$tmp_root"
  fi
}

pass() {
  pass_count=$((pass_count + 1))
  echo "ok - $1"
}

fail() {
  fail_count=$((fail_count + 1))
  echo "not ok - $1"
}

# Isolated HOME + git repo with a committed main and a starter .fleet/ table.
# Sets REPO (not printed) so callers can avoid command-substitution subshells.
make_repo() {
  [ -n "$tmp_root" ] || die "tmp_root unset"
  repo_n=$((repo_n + 1))
  home="$tmp_root/home"
  REPO="$tmp_root/repo-$repo_n"
  mkdir -p "$home" "$REPO"
  export HOME="$home"
  export GIT_CONFIG_NOSYSTEM=1
  export GIT_CONFIG_GLOBAL=/dev/null
  git -C "$REPO" init -q -b main
  git -C "$REPO" config user.email test@example.com
  git -C "$REPO" config user.name test
  printf 'seed\n' > "$REPO/README"
  git -C "$REPO" add README
  git -C "$REPO" commit -qm seed >/dev/null
  mkdir -p "$REPO/.fleet"
  printf '%s\n' \
    '| id | shape | fleet-worker | status | tab | branch | base | updated |' \
    '| --- | --- | --- | --- | --- | --- | --- | --- |' \
    > "$REPO/.fleet/tasks.md"
  printf '%s\n' 'kind: pi' 'model: test-model' 'effort: high' > "$REPO/.fleet/config.md"
}

append_row() {
  # append_row <tasks.md> <id> <shape> <status> <branch>
  printf '| %s | %s | pi | %s | - | %s | main | 2026-01-01T00:00Z |\n' \
    "$2" "$3" "$4" "$5" >> "$1"
}

row_status() {
  # row_status <tasks.md> <id>
  awk -F'|' -v id="$2" '
    /^\|/ {
      s=$2; gsub(/^[ \t]+|[ \t]+$/,"",s)
      if (s==id) { v=$5; gsub(/^[ \t]+|[ \t]+$/,"",v); print v; exit }
    }' "$1"
}

install_herdr() {
  # install_herdr <bin-dir> <log-file> [prompt-exit]
  # Logs every argv line. tab create / agent start / agent get succeed.
  # agent prompt exits with prompt-exit (default 0).
  bin="$1"
  log="$2"
  prompt_exit="${3:-0}"
  mkdir -p "$bin"
  cat > "$bin/herdr" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$log"
case "\${1-} \${2-}" in
  "tab create")
    printf '%s\n' '{"result":{"tab":{"tab_id":"tab-1"},"root_pane":{"pane_id":"pane-1"}}}'
    exit 0
    ;;
  "agent start")
    printf '%s\n' '{"ok":true}'
    exit 0
    ;;
  "agent get")
    printf '%s\n' '{"result":{"agent":{"agent_status":"idle"}}}'
    exit 0
    ;;
  "agent prompt")
    echo "herdr: agent prompt failed" >&2
    exit $prompt_exit
    ;;
  "agent wait"|"tab close"|"pane list"|"agent rename"|"tab rename")
    printf '%s\n' '{"result":{}}'
    exit 0
    ;;
  *)
    printf '%s\n' '{"result":{}}'
    exit 0
    ;;
esac
EOF
  chmod +x "$bin/herdr"
}
