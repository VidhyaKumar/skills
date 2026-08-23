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

test_guard_bash_allowlist_denies() {
  name="fleet-guard.sh Bash allowlist refuses every known write channel"
  make_repo
  repo="$REPO"
  touch "$repo/.fleet/active"
  # One case per bypass class the verb blocklist could not close.
  set -- \
    'rm -rf src' \
    '/bin/rm -rf src' \
    '\rm -rf src' \
    'echo "rm -rf src" | bash' \
    'bash -c "rm -rf src"' \
    'cat script.sh | sh' \
    'python3 -c "open(chr(120),chr(119)).write(chr(121))"' \
    'perl -e "unlink q(src/a)"' \
    'git --work-tree=. reset --hard' \
    'git checkout -- src/a' \
    'git branch -D main' \
    'git worktree add /tmp/x' \
    'echo $(rm -rf src)' \
    'echo `rm -rf src`' \
    'sed -i "" s/a/b/ src/a' \
    'echo x | tee src/a' \
    'echo x > src/a' \
    'echo x >> ../outside' \
    'true; rm -rf src' \
    'true && rm -rf src' \
    'find . -delete' \
    'find . -name x -exec rm {} +' \
    'awk "BEGIN{print 1 > \"src/a\"}"' \
    'sort -o src/a src/a' \
    'sed "w src/a" src/a' \
    'yq -i ".a=1" src/a' \
    'command rm -rf src' \
    'env rm -rf src' \
    'env FOO=1 rm -rf src' \
    'less src/a' \
    'grep "a|b" src/a; rm -rf src' \
    'echo "x;rm -rf src" | bash' \
    'bash -c "rm -rf src; ls"'
  bad=""
  for c in "$@"; do
    guard_bash "$repo" "$c"
    [ "$GUARD_RC" -eq 2 ] || bad="$bad
    allowed: $c (exit=$GUARD_RC)"
  done
  if [ -z "$bad" ]; then
    pass "$name"
  else
    fail "$name$bad"
  fi
}

test_guard_bash_allowlist_permits() {
  name="fleet-guard.sh Bash allowlist still permits documented orchestrator commands"
  make_repo
  repo="$REPO"
  touch "$repo/.fleet/active"
  # Every command shape SKILL.md tells the fleet-manager to run.
  set -- \
    'git status --porcelain' \
    'git -C /tmp/x diff --stat' \
    'git log --oneline -5' \
    'git merge --no-ff fleet/alpha' \
    'git worktree list' \
    'cat .fleet/tasks.md' \
    'grep -n alpha .fleet/tasks.md | head -5' \
    'herdr agent list' \
    "\"$scripts_dir/fleet-mode.sh\" on" \
    "sh \"$scripts_dir/fleet-task.sh\" status alpha working" \
    'echo hi > /dev/null' \
    'echo hi > .fleet/note.md' \
    'printf x >> /tmp/scratch' \
    'uniq .fleet/tasks.md' \
    'cut -d"|" -f2 .fleet/tasks.md' \
    'stat .fleet/tasks.md' \
    'readlink .fleet/tasks.md' \
    'sleep 1' \
    'ps aux' \
    'find . -name "*.md"' \
    'cat .fleet/tasks.md | sort | uniq -c' \
    'grep "a|b" .fleet/tasks.md' \
    'git log --format="%h > %s"' \
    "nohup sh \"$scripts_dir/fleet-watch.sh\" alpha pane-1 >/dev/null 2>&1 &"
  bad=""
  for c in "$@"; do
    guard_bash "$repo" "$c"
    [ "$GUARD_RC" -eq 0 ] || bad="$bad
    blocked: $c (exit=$GUARD_RC, $(head -1 "$tmp_root/guard-bash.err"))"
  done
  if [ -z "$bad" ]; then
    pass "$name"
  else
    fail "$name$bad"
  fi
}

test_guard_fleet_write_through_symlinked_cwd() {
  name="fleet-guard.sh allows .fleet/ writes when cwd differs from git toplevel by symlink"
  make_repo
  repo="$REPO"
  touch "$repo/.fleet/active"
  # macOS: payload cwd is /tmp/..., git rev-parse reports /private/tmp/...
  # A $root-anchored path check denies every legitimate .fleet/ write here.
  real="$(CDPATH='' cd -- "$repo" && pwd -P)"
  if [ "$real" = "$repo" ]; then
    link="$tmp_root/link-repo"
    rm -f "$link"
    ln -s "$repo" "$link" || {
      fail "$name (could not create symlink)"
      return
    }
    cwd="$link"
  else
    cwd="$repo"
  fi
  bad=""
  guard_write "$cwd" ".fleet/tasks.md"
  [ "$GUARD_RC" -eq 0 ] || bad="$bad relative=$GUARD_RC"
  guard_write "$cwd" "$cwd/.fleet/tasks.md"
  [ "$GUARD_RC" -eq 0 ] || bad="$bad absolute=$GUARD_RC"
  guard_write "$cwd" ".fleet/../src/app.ts"
  [ "$GUARD_RC" -eq 2 ] || bad="$bad traversal=$GUARD_RC"
  if [ -z "$bad" ]; then
    pass "$name"
  else
    fail "$name ($bad)"
  fi
}

test_teardown_refuses_before_destroying() {
  name="fleet-task.sh teardown refuses unmerged commits and dirty worktrees without destroying"
  make_repo
  repo="$REPO"
  cd "$repo" || exit 1
  out="$(sh "$task_sh" create keep-me ship main 2>/dev/null)" || {
    fail "$name (create failed: $out)"
    return
  }
  dir="$(printf '%s\n' "$out" | sed -n 's/^dir=//p')"
  [ -n "$dir" ] && [ -d "$dir" ] || {
    fail "$name (no worktree dir from create)"
    return
  }
  printf 'work\n' >> "$dir/README"
  git -C "$dir" commit -qam 'unmerged work'
  # A refusal that lands after the watcher is stopped is still a destructive
  # teardown, and the worktree survives either way (git worktree remove
  # refuses a dirty tree). The pidfile is what distinguishes "refused before
  # touching anything" from "refused halfway through".
  pidfile="$repo/.fleet/keep-me.watch.pid"

  bad=""
  # 1. Unmerged commits: refuse before destroying anything.
  printf '1\n' > "$pidfile"
  if sh "$task_sh" teardown keep-me >/dev/null 2>"$tmp_root/td1.err"; then
    bad="$bad unmerged_exit=0"
  fi
  [ -d "$dir" ] || bad="$bad worktree_destroyed_on_unmerged"
  [ -f "$pidfile" ] || bad="$bad watcher_stopped_on_unmerged"
  git -C "$repo" show-ref --verify --quiet refs/heads/fleet/keep-me \
    || bad="$bad branch_destroyed_on_unmerged"

  # 2. Merged but untracked file present: still refuse, still before anything.
  git -C "$repo" merge -q --no-ff -m merge fleet/keep-me
  printf 'scratch\n' > "$dir/untracked.txt"
  printf '1\n' > "$pidfile"
  if sh "$task_sh" teardown keep-me >/dev/null 2>"$tmp_root/td2.err"; then
    bad="$bad untracked_exit=0"
  fi
  [ -d "$dir" ] || bad="$bad worktree_destroyed_on_untracked"
  [ -f "$pidfile" ] || bad="$bad watcher_stopped_on_untracked"

  # 3. Clean: succeeds and removes both.
  rm -f "$dir/untracked.txt"
  if sh "$task_sh" teardown keep-me >/dev/null 2>"$tmp_root/td3.err"; then
    :
  else
    bad="$bad clean_exit=$?"
  fi
  [ -d "$dir" ] && bad="$bad worktree_left"
  git -C "$repo" show-ref --verify --quiet refs/heads/fleet/keep-me \
    && bad="$bad branch_left"

  if [ -z "$bad" ]; then
    pass "$name"
  else
    fail "$name ($bad)"
  fi
}

test_teardown_stops_watcher_by_identity() {
  name="fleet-task.sh teardown kills its own watcher but not a recycled pid"
  make_repo
  repo="$REPO"
  cd "$repo" || exit 1
  out="$(sh "$task_sh" create watched ship main 2>/dev/null)" || {
    fail "$name (create failed: $out)"
    return
  }
  # A live process whose argv does not look like a watcher must survive:
  # teardown must verify pid identity, not just kill whatever the pidfile says.
  sleep 30 &
  bystander=$!
  printf '%s\n' "$bystander" > "$repo/.fleet/watched.watch.pid"
  sh "$task_sh" teardown watched --force-branch >/dev/null 2>&1
  bad=""
  kill -0 "$bystander" 2>/dev/null || bad="$bad killed_unrelated_pid"
  kill "$bystander" 2>/dev/null || true
  wait "$bystander" 2>/dev/null || true
  [ -f "$repo/.fleet/watched.watch.pid" ] && bad="$bad pidfile_left"
  if [ -z "$bad" ]; then
    pass "$name"
  else
    fail "$name ($bad)"
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
test_guard_bash_allowlist_denies
test_guard_bash_allowlist_permits
test_guard_fleet_write_through_symlinked_cwd
test_teardown_refuses_before_destroying
test_teardown_stops_watcher_by_identity

echo "---"
echo "$pass_count passed, $fail_count failed"
[ "$fail_count" -eq 0 ]
