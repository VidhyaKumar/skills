#!/bin/sh
# Minimal portable runner for skills/fleet public-seam regressions.
# Usage: sh tests/fleet/run.sh
# shellcheck disable=SC1090,SC1091,SC2153,SC2154
set -u

tests_dir="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)" || exit 1
cd "$tests_dir" || exit 1
. "$tests_dir/helpers.sh"

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/fleet-tests.XXXXXX")"
trap cleanup EXIT

test_stale_lock_dead_pid() {
  name="fleet-task.sh status succeeds when tasks.lock has dead-looking content"
  make_repo
  repo="$REPO"
  tasks="$repo/.fleet/tasks.md"
  append_row "$tasks" alpha scout queued -
  sh -c 'exit 0' &
  dead=$!
  wait "$dead" || true
  lock="$repo/.fleet/tasks.lock"
  if ! printf '%s\n' "$dead" > "$lock"; then
    fail "$name (could not create lock)"
    return
  fi
  cd "$repo" || exit 1
  if sh "$task_sh" status alpha working >/dev/null 2>"$tmp_root/stale-lock.err"; then
    rc=0
  else
    rc=$?
  fi
  st="$(row_status "$tasks" alpha)"
  if [ -d "$lock" ]; then
    lock_dir=1
  else
    lock_dir=0
  fi
  if [ "$rc" -eq 0 ] && [ "$st" = "working" ] && [ "$lock_dir" -eq 0 ]; then
    pass "$name"
  else
    fail "$name (exit=$rc status=$st lock_dir=$lock_dir)"
  fi
}

test_concurrent_status() {
  name="concurrent fleet-task.sh status mutations both persist"
  make_repo
  repo="$REPO"
  tasks="$repo/.fleet/tasks.md"
  append_row "$tasks" alpha scout queued -
  append_row "$tasks" bravo scout queued -
  # Widen the read/write window so the lost-update race is not luck-dependent.
  i=1
  while [ "$i" -le 400 ]; do
    append_row "$tasks" "pad-$i" scout queued -
    i=$((i + 1))
  done

  lost=0
  trial=1
  while [ "$trial" -le 15 ]; do
    # Reset only the two live rows; padding stays.
    awk -F'|' -v OFS='|' '
      /^\|/ {
        s=$2; gsub(/^[ \t]+|[ \t]+$/,"",s)
        if (s=="alpha" || s=="bravo") $5=" queued "
      }
      { print }
    ' "$tasks" > "$tasks.reset" && mv "$tasks.reset" "$tasks"

    gate="$tmp_root/gate.$trial"
    ready1="$tmp_root/ready1.$trial"
    ready2="$tmp_root/ready2.$trial"
    rm -f "$gate" "$ready1" "$ready2"
    (
      cd "$repo" || exit 1
      touch "$ready1"
      while [ ! -f "$gate" ]; do :; done
      sh "$task_sh" status alpha working >/dev/null 2>&1
    ) &
    p1=$!
    (
      cd "$repo" || exit 1
      touch "$ready2"
      while [ ! -f "$gate" ]; do :; done
      sh "$task_sh" status bravo blocked >/dev/null 2>&1
    ) &
    p2=$!
    while [ ! -f "$ready1" ] || [ ! -f "$ready2" ]; do :; done
    touch "$gate"
    wait "$p1" "$p2" || true

    a="$(row_status "$tasks" alpha)"
    b="$(row_status "$tasks" bravo)"
    if [ "$a" != "working" ] || [ "$b" != "blocked" ]; then
      lost=1
      break
    fi
    trial=$((trial + 1))
  done

  if [ "$lost" -eq 0 ] && [ "$(row_status "$tasks" alpha)" = "working" ] \
    && [ "$(row_status "$tasks" bravo)" = "blocked" ]; then
    pass "$name"
  else
    fail "$name (alpha=$(row_status "$tasks" alpha) bravo=$(row_status "$tasks" bravo))"
  fi
}

test_teardown_force_branch() {
  name="fleet-task.sh teardown --force-branch removes dirty worktree and branch"
  make_repo
  repo="$REPO"
  cd "$repo" || exit 1
  out="$(sh "$task_sh" create dirty-wt ship main 2>/dev/null)" || {
    fail "$name (create failed: $out)"
    return
  }
  dir="$(printf '%s\n' "$out" | sed -n 's/^dir=//p')"
  [ -n "$dir" ] && [ -d "$dir" ] || {
    fail "$name (no worktree dir from create)"
    return
  }
  printf 'dirty\n' >> "$dir/README"
  printf 'untracked\n' > "$dir/extra.txt"
  git -C "$dir" add extra.txt
  git -C "$dir" commit -qm 'unmerged work'

  if sh "$task_sh" teardown dirty-wt --force-branch >/dev/null 2>"$tmp_root/teardown.err"; then
    rc=0
  else
    rc=$?
  fi

  still_wt=0
  git -C "$repo" worktree list --porcelain | grep -q "$dir" && still_wt=1
  [ -d "$dir" ] && still_wt=1
  still_br=0
  git -C "$repo" show-ref --verify --quiet refs/heads/fleet/dirty-wt && still_br=1

  if [ "$rc" -eq 0 ] && [ "$still_wt" -eq 0 ] && [ "$still_br" -eq 0 ]; then
    pass "$name"
  else
    fail "$name (exit=$rc worktree_left=$still_wt branch_left=$still_br)"
  fi
}

test_guard_apply_patch_mixed() {
  name="fleet-guard.sh rejects apply_patch touching .fleet/ and a non-.fleet path"
  make_repo
  repo="$REPO"
  touch "$repo/.fleet/active"
  payload="$tmp_root/apply_patch.json"
  cat > "$payload" <<EOF
{
  "tool_name": "apply_patch",
  "cwd": "$repo",
  "tool_input": {
    "input": "*** Begin Patch\\n*** Update File: .fleet/tasks.md\\n@@\\n+ok\\n*** End Patch\\n*** Begin Patch\\n*** Add File: src/app.ts\\n+export {}\\n*** End Patch\\n"
  }
}
EOF
  if bash "$guard_sh" < "$payload" >/dev/null 2>"$tmp_root/guard.err"; then
    rc=0
  else
    rc=$?
  fi
  if [ "$rc" -eq 2 ]; then
    pass "$name"
  else
    fail "$name (exit=$rc, want 2)"
  fi
}

test_guard_apply_patch_move_to() {
  name="fleet-guard.sh rejects apply_patch moving .fleet/ path to src/"
  make_repo
  repo="$REPO"
  touch "$repo/.fleet/active"
  payload="$tmp_root/apply_patch_move.json"
  cat > "$payload" <<EOF
{
  "tool_name": "apply_patch",
  "cwd": "$repo",
  "tool_input": {
    "input": "*** Begin Patch\\n*** Update File: .fleet/x\\n*** Move to: src/x\\n@@\\n+ok\\n*** End Patch\\n"
  }
}
EOF
  if bash "$guard_sh" < "$payload" >/dev/null 2>"$tmp_root/guard_move.err"; then
    rc=0
  else
    rc=$?
  fi
  if [ "$rc" -eq 2 ]; then
    pass "$name"
  else
    fail "$name (exit=$rc, want 2)"
  fi
}

test_guard_apply_patch_path_no_expansion() {
  name="fleet-guard.sh does not execute command substitution in apply_patch paths"
  make_repo
  repo="$REPO"
  touch "$repo/.fleet/active"
  sentinel="$tmp_root/guard-expand.sentinel"
  rm -f "$sentinel"
  payload="$tmp_root/apply_patch_expand.json"
  cat > "$payload" <<EOF
{
  "tool_name": "apply_patch",
  "cwd": "$repo",
  "tool_input": {
    "input": "*** Begin Patch\\n*** Add File: .fleet/\$(touch $sentinel)\\n+ok\\n*** End Patch\\n"
  }
}
EOF
  if bash "$guard_sh" < "$payload" >/dev/null 2>"$tmp_root/guard_expand.err"; then
    rc=0
  else
    rc=$?
  fi
  if [ "$rc" -eq 0 ] && [ ! -f "$sentinel" ]; then
    pass "$name"
  else
    if [ -f "$sentinel" ]; then
      sent=exists
    else
      sent=absent
    fi
    fail "$name (exit=$rc, want 0; sentinel=$sent)"
  fi
}

test_dispatch_claude_effort() {
  name="fleet-dispatch.sh kind=claude passes configured effort as --effort"
  make_repo
  repo="$REPO"
  printf '%s\n' 'kind: claude' 'model: sonnet' 'effort: high' > "$repo/.fleet/config.md"
  append_row "$repo/.fleet/tasks.md" send-it scout queued -
  printf 'brief\n' > "$repo/.fleet/send-it.brief.md"
  log="$tmp_root/herdr.dispatch.log"
  : > "$log"
  install_herdr "$tmp_root/bin" "$log" 0
  export PATH="$tmp_root/bin:$PATH"
  export HERDR_PANE_ID=pane-mgr
  cd "$repo" || exit 1
  if sh "$dispatch_sh" send-it >/dev/null 2>"$tmp_root/dispatch.err"; then
    rc=0
  else
    rc=$?
  fi
  start_line="$(grep '^agent start ' "$log" | head -1)"
  has_effort=1
  printf '%s\n' "$start_line" | grep -q -- '--effort' || has_effort=0
  printf '%s\n' "$start_line" | grep -Eq -- '--effort(=|[[:space:]])high([[:space:]]|$)' || has_effort=0
  if [ "$rc" -eq 0 ] && [ "$has_effort" -eq 1 ]; then
    pass "$name"
  else
    fail "$name (exit=$rc start_argv=${start_line:-<none>})"
  fi
}

test_watch_retry_observable() {
  name="fleet-watch.sh retries failed manager-event delivery and does not silently succeed once"
  make_repo
  repo="$REPO"
  log="$tmp_root/herdr.watch.log"
  : > "$log"
  install_herdr "$tmp_root/bin" "$log" 1
  export PATH="$tmp_root/bin:$PATH"
  cd "$repo" || exit 1
  out="$tmp_root/watch.out"
  err="$tmp_root/watch.err"
  : > "$out"
  : > "$err"
  sh "$watch_sh" send-it pane-mgr >"$out" 2>"$err" &
  pid=$!
  n=0
  while [ "$n" -lt 8 ]; do
    if ! kill -0 "$pid" 2>/dev/null; then
      break
    fi
    sleep 1
    n=$((n + 1))
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    hung=1
  else
    wait "$pid"
    rc=$?
    hung=0
  fi
  prompts="$(grep -c '^agent prompt ' "$log" || true)"
  visible=0
  if grep -qiE 'fail|retry|error|undeliver|FLEET-EVENT' "$out" "$err" 2>/dev/null; then
    visible=1
  fi
  # Forbidden current behavior: one swallowed prompt and no retry.
  # Required: at least one retry, and failure must be visible (log or non-zero
  # after retries — not a single silent attempt).
  if [ "$hung" -eq 0 ] && [ "$prompts" -ge 2 ] && {
    [ "$visible" -eq 1 ] || [ "$rc" -ne 0 ]
  }; then
    pass "$name"
  else
    fail "$name (prompts=$prompts visible=$visible hung=$hung exit=${rc:-timeout})"
  fi
}

test_stale_lock_dead_pid
test_concurrent_status
test_teardown_force_branch
test_guard_apply_patch_mixed
test_guard_apply_patch_move_to
test_guard_apply_patch_path_no_expansion
test_dispatch_claude_effort
test_watch_retry_observable

echo "---"
echo "$pass_count passed, $fail_count failed"
[ "$fail_count" -eq 0 ]
