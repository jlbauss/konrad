#!/usr/bin/env bats
# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# bin/konrad's watchdog (bounded) and its user with the most at stake, the org
# post-sync hook (org_run_hook). Plain bash, no engine.

load helpers

@test "bounded: passes the command's status through" {
  k 'bounded 5 false'
  [ "$status" -eq 1 ]
}

@test "bounded: returns 124 and kills the command at the ceiling" {
  start=$SECONDS
  k 'bounded 1 sleep 30'
  [ "$status" -eq 124 ]
  [ $((SECONDS - start)) -lt 5 ]
}

@test "bounded: a capture gets the output and returns at once, not at the ceiling" {
  start=$SECONDS
  k 'bounded 30 echo hi'
  [ "$output" = hi ]
  [ $((SECONDS - start)) -lt 5 ]
}

# The background refresh worker ignores INT/HUP/TERM; the watchdog must still
# end a slow command by its SIGKILL backstop.
@test "bounded: with TERM ignored, still times out" {
  start=$SECONDS
  k 'trap "" INT HUP TERM; bounded 1 sleep 30'
  [ "$status" -eq 124 ]
  [ $((SECONDS - start)) -lt 8 ]
}

@test "bounded: leaves no watchdog sleep behind" {
  # Output to /dev/null, so a leftover sleep can't hold run's capture open
  # until it ends by itself.
  k 'for i in 1 2 3 4 5 6 7 8 9 10; do bounded 47 true; done >/dev/null 2>&1'
  [ "$status" -eq 0 ]
  [ -z "$(pgrep -f 'sleep 47' || true)" ]
}

# --- org_run_hook -------------------------------------------------------------

layer() {  # $1 name, $2 hook body: an org layer dir with that hooks/post-sync
  mkdir -p "$BATS_TEST_TMPDIR/org/$1/hooks"
  printf '#!/bin/sh\n%s\n' "$2" >"$BATS_TEST_TMPDIR/org/$1/hooks/post-sync"
  chmod +x "$BATS_TEST_TMPDIR/org/$1/hooks/post-sync"
}

notices() { echo "$HOME/.local/state/konrad/notices"; }

@test "org_run_hook: the hook gets its environment, and success leaves no notice" {
  # shellcheck disable=SC2016  # expanded by the hook, not here
  layer good 'echo "$KONRAD_LAYER_NAME $KONRAD_HOOK_INTERACTIVE" >"$KONRAD_NOTICE_DIR/../env-seen"'
  k "org_run_hook '$BATS_TEST_TMPDIR/org/good' 2>/dev/null"
  [ "$(cat "$(notices)/env-seen")" = "good 0" ]
  [ -z "$(ls -A "$(notices)/org-good" 2>/dev/null)" ]
}

@test "org_run_hook: a failing hook leaves a failure notice" {
  layer failing 'echo "something broke"; exit 3'
  k "org_run_hook '$BATS_TEST_TMPDIR/org/failing' 2>/dev/null"
  [ -f "$(notices)/org-failing/hook-failure" ]
}

@test "org_run_hook: a slow hook is killed at KONRAD_HOOK_TIMEOUT and leaves a timeout notice" {
  layer slow 'exec sleep 30'
  export KONRAD_HOOK_TIMEOUT=1
  start=$SECONDS
  k "org_run_hook '$BATS_TEST_TMPDIR/org/slow' 2>/dev/null"
  [ $((SECONDS - start)) -lt 5 ]
  [ -f "$(notices)/org-slow/hook-timeout" ]
}
