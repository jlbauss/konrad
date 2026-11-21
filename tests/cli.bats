#!/usr/bin/env bats
# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# bin/konrad's host-side logic: the paths that run before any container, where
# nothing else tests them. Each case covers the empty, missing and malformed
# input next to the good one.

load helpers

# --- engine choice --------------------------------------------------------------

@test "detect_engine: container on macOS, even before its CLI is installed" {
  k 'uname() { [[ "$1" == -s ]] && echo Darwin || echo arm64; }
     detect_engine; echo "$KONRAD_ENGINE"'
  [ "$status" -eq 0 ]
  [ "$output" = container ]
}

@test "detect_engine: podman on Linux" {
  k 'uname() { [[ "$1" == -s ]] && echo Linux || echo x86_64; }
     detect_engine; echo "$KONRAD_ENGINE"'
  [ "$status" -eq 0 ]
  [ "$output" = podman ]
}

@test "detect_engine: KONRAD_ENGINE wins over the OS" {
  k 'uname() { echo Darwin; }; KONRAD_ENGINE=podman; detect_engine; echo "$KONRAD_ENGINE"'
  [ "$output" = podman ]
}

@test "detect_engine: an unknown KONRAD_ENGINE is refused" {
  k 'KONRAD_ENGINE=docker; detect_engine'
  [ "$status" -ne 0 ]
  [[ "$output" == *"KONRAD_ENGINE must be 'podman' or 'container'"* ]]
}

@test "engine_missing on macOS names what container needs, not Podman" {
  k 'KONRAD_ENGINE=container; engine_missing'
  [ "$status" -eq 1 ]
  [[ "$output" == *"macOS 26"* ]]
  [[ "$output" != *"podman"* ]]
}

# --- resource defaults ------------------------------------------------------------

@test "default_memory: half the host, clamped to 2G..8G and to the host" {
  k 'host_mem_mib() { echo 32768; }; default_memory'; [ "$output" = 8G ]
  k 'host_mem_mib() { echo 8192; };  default_memory'; [ "$output" = 4G ]
  k 'host_mem_mib() { echo 3000; };  default_memory'; [ "$output" = 2G ]
  k 'host_mem_mib() { echo 1500; };  default_memory'; [ "$output" = 1500M ]
  k 'host_mem_mib() { echo 65536; }; default_memory 16384'; [ "$output" = 16G ]
}

@test "default_memory: an unreadable host total falls back to 4G" {
  k 'host_mem_mib() { :; };        default_memory'; [ "$status" -eq 0 ]; [ "$output" = 4G ]
  k 'host_mem_mib() { echo abc; }; default_memory'; [ "$status" -eq 0 ]; [ "$output" = 4G ]
  k 'host_mem_mib() { echo 0; };   default_memory'; [ "$status" -eq 0 ]; [ "$output" = 4G ]
}

@test "default_cpus: all but two, clamped to 2..8 and to the host" {
  k 'host_cpu_count() { echo 16; }; default_cpus'; [ "$output" = 8 ]
  k 'host_cpu_count() { echo 6; };  default_cpus'; [ "$output" = 4 ]
  k 'host_cpu_count() { echo 3; };  default_cpus'; [ "$output" = 2 ]
  k 'host_cpu_count() { echo 1; };  default_cpus'; [ "$output" = 1 ]
}

@test "default_cpus: an unreadable host count falls back to 4" {
  k 'host_cpu_count() { :; };      default_cpus'; [ "$status" -eq 0 ]; [ "$output" = 4 ]
  k 'host_cpu_count() { echo x; }; default_cpus'; [ "$status" -eq 0 ]; [ "$output" = 4 ]
}

@test "retention_days: default 30, malformed reads as disabled" {
  k 'retention_days';                              [ "$output" = 30 ]
  k 'KONRAD_RETENTION_DAYS=7 retention_days';      [ "$output" = 7 ]
  k 'KONRAD_RETENTION_DAYS=abc retention_days';    [ "$output" = 0 ]
  k 'KONRAD_RETENTION_DAYS=-1 retention_days';     [ "$output" = 0 ]
  k 'KONRAD_RETENTION_DAYS= retention_days';       [ "$output" = 30 ]
}

# --- background refresh throttle --------------------------------------------------
# The 0.22.0 first-launch crash lived here: reading a missing stamp aborted the
# launch under pipefail. The stubs replace the engine and the worker; the
# worker stub leaves a marker, so "fired" is observable.

refresh() {
  k 'is_dev() { return 1; }
     eng_image_exists() { return 0; }
     eng_image_id() { echo sha256:base; }
     _refresh_worker() { echo "fired $1" > "$HOME/fired"; }
     '"$1"'
     maybe_background_refresh; wait
     [[ -f "$HOME/fired" ]] && cat "$HOME/fired" || echo "not fired"'
}

@test "refresh: no stamp yet (first launch) fires and writes the stamp" {
  refresh ''
  [ "$status" -eq 0 ]
  [ "$output" = "fired sha256:base" ]
  [ -s "$HOME/.local/state/konrad/last-refresh" ] || ls -R "$HOME" >&3
}

@test "refresh: a fresh stamp is throttled" {
  refresh 'mkdir -p "$KONRAD_STATE_DIR"; date +%s > "$KONRAD_REFRESH_STAMP"'
  [ "$status" -eq 0 ]
  [ "$output" = "not fired" ]
}

@test "refresh: a stale stamp fires" {
  refresh 'mkdir -p "$KONRAD_STATE_DIR"; echo $(( $(date +%s) - 90000 )) > "$KONRAD_REFRESH_STAMP"'
  [ "$output" = "fired sha256:base" ]
}

@test "refresh: an empty or garbage stamp fires instead of crashing" {
  refresh 'mkdir -p "$KONRAD_STATE_DIR"; : > "$KONRAD_REFRESH_STAMP"'
  [ "$status" -eq 0 ]; [ "$output" = "fired sha256:base" ]
  rm -f "$HOME/fired"
  refresh 'mkdir -p "$KONRAD_STATE_DIR"; echo "not a number" > "$KONRAD_REFRESH_STAMP"'
  [ "$status" -eq 0 ]; [ "$output" = "fired sha256:base" ]
}

@test "refresh: interval 0 disables, a malformed interval means daily" {
  refresh 'KONRAD_REFRESH_INTERVAL=0'
  [ "$output" = "not fired" ]
  refresh 'KONRAD_REFRESH_INTERVAL=soon; mkdir -p "$KONRAD_STATE_DIR"; date +%s > "$KONRAD_REFRESH_STAMP"'
  [ "$status" -eq 0 ]; [ "$output" = "not fired" ]
}

@test "refresh: never from konrad-dev, never with the opt-out" {
  k 'is_dev() { return 0; }; _refresh_worker() { touch "$HOME/fired"; }
     maybe_background_refresh; wait; [[ ! -e "$HOME/fired" ]]'
  [ "$status" -eq 0 ]
  k 'is_dev() { return 1; }; eng_image_exists() { return 0; }
     _refresh_worker() { touch "$HOME/fired"; }
     KONRAD_NO_AUTO_REFRESH=1 maybe_background_refresh; wait; [[ ! -e "$HOME/fired" ]]'
  [ "$status" -eq 0 ]
}

# --- notice queue ------------------------------------------------------------------

@test "notices: no notices dir is a no-op" {
  k 'notices_flush'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "notices: an emitted notice renders once, then is gone" {
  k 'notice_emit test-note warn "the summary" "a detail" "the fix"
     notices_flush; echo "--"; notices_flush; ls -A "$KONRAD_NOTICES_DIR"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"the summary"* ]]
  [[ "$output" == *"a detail"* ]]
  [[ "$output" == *"fix: the fix"* ]]
  [ "${output#*--}" = "" ]
}

@test "notices: a malformed file renders nothing and is still drained" {
  k 'mkdir -p "$KONRAD_NOTICES_DIR"
     printf "no colon here\nseverity: warn\n" > "$KONRAD_NOTICES_DIR/broken"
     : > "$KONRAD_NOTICES_DIR/empty"
     notices_flush; ls -A "$KONRAD_NOTICES_DIR"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "notices: escape sequences and control characters are stripped" {
  k 'mkdir -p "$KONRAD_NOTICES_DIR"
     printf "severity: warn\nsummary: \033[31mred\033[0m\007 text\n" > "$KONRAD_NOTICES_DIR/esc"
     notices_flush 2>&1 | od -c'
  [ "$status" -eq 0 ]
  [[ "$output" != *"033"* ]]
  [[ "$output" != *"007"* ]]
}

@test "notices: an org layer's notice is attributed by path and its dir removed" {
  k 'mkdir -p "$KONRAD_NOTICES_DIR/org-acme"
     printf "severity: info\nsummary: hello from acme\n" > "$KONRAD_NOTICES_DIR/org-acme/n"
     notices_flush; [[ ! -e "$KONRAD_NOTICES_DIR/org-acme" ]] && echo drained'
  [ "$status" -eq 0 ]
  [[ "$output" == *"From your organization layer acme: hello from acme"* ]]
  [[ "$output" == *drained* ]]
}

@test "notices: KONRAD_NO_NOTICES leaves the queue for a later launch" {
  k 'notice_emit kept info "keep me"; KONRAD_NO_NOTICES=1 notices_flush; ls "$KONRAD_NOTICES_DIR"'
  [ "$status" -eq 0 ]
  [ "$output" = kept ]
}

# --- version -------------------------------------------------------------------------

@test "reread_baked_version: picks up the installer's rewrite, keeps the old value on a miss" {
  printf '#!/usr/bin/env bash\nKONRAD_VERSION_BAKED="9.8.7"  # rewritten\n' > "$BATS_TEST_TMPDIR/baked"
  printf '#!/usr/bin/env bash\n' > "$BATS_TEST_TMPDIR/unbaked"
  # It reads "$0" (the installed script), so run it with $0 set to each file.
  run bash -c 'KONRAD_SOURCE_ONLY=1 source "$1"; KONRAD_VERSION=old
               reread_baked_version; echo "$KONRAD_VERSION"' "$BATS_TEST_TMPDIR/baked" "$KONRAD"
  [ "$output" = 9.8.7 ]
  run bash -c 'KONRAD_SOURCE_ONLY=1 source "$1"; KONRAD_VERSION=old
               reread_baked_version; echo "$KONRAD_VERSION"' "$BATS_TEST_TMPDIR/unbaked" "$KONRAD"
  [ "$status" -eq 0 ]
  [ "$output" = old ]
}

# --- konrad code input ------------------------------------------------------------------

@test "code_normalize_url: https and ssh spellings become one https .git URL" {
  k 'code_normalize_url https://gitlab.example.com/group/repo';      [ "$output" = https://gitlab.example.com/group/repo.git ]
  k 'code_normalize_url https://gitlab.example.com/group/repo.git/'; [ "$output" = https://gitlab.example.com/group/repo.git ]
  k 'code_normalize_url git@gitlab.example.com:group/sub/repo.git';  [ "$output" = https://gitlab.example.com/group/sub/repo.git ]
  k 'code_normalize_url ssh://git@gitlab.example.com:2222/group/repo'; [ "$output" = https://gitlab.example.com/group/repo.git ]
}

@test "code_normalize_url: credentials, bare hosts and junk are refused" {
  for u in https://user:tok@gitlab.example.com/g/r https://gitlab.example.com/repo \
           http://gitlab.example.com/g/r "" "gitlab.example.com/g/r" "https://gitlab.example.com/g/r;rm"; do
    k "code_normalize_url '$u'"
    [ "$status" -ne 0 ] || { echo "accepted: $u" >&3; false; }
    [[ "$output" == *"needs an https or ssh git URL"* ]]
  done
}

@test "code_volume_name: one volume per repo path, safe characters only" {
  k 'code_volume_name https://GitLab.Example.com/Group/My_Repo.git'
  [ "$output" = konrad-code-gitlab.example.com-group-my-repo ]
}

@test "code_session_valid: short lowercase names only" {
  k 'code_session_valid s2'; [ "$status" -eq 0 ]
  k 'code_session_valid primary'; [ "$status" -eq 0 ]
  for s in "" S2 -lead "has space" "$(printf 'a%.0s' {1..40})" "../x"; do
    k "code_session_valid '$s'"
    [ "$status" -ne 0 ] || { echo "accepted: $s" >&3; false; }
  done
}

# --- konrad code up's markers: up --all, restart, down --all ----------------------

# Two marked repos, one under --profile p; the engine stubbed to log each stop,
# removal and start to $HOME/calls (konrad captures a removal's own output).
markers='mkdir -p "$CODE_UP_DIR"
  printf "url=https://h/o/a.git\nprofile=\ncapacity=2\nnested=0\nkvm=0\nmemory=12g\narg=--verbose\n" > "$CODE_UP_DIR/konrad-up-h-o-a"
  printf "url=https://h/o/b.git\nprofile=p\ncapacity=4\nnested=1\nkvm=1\n" > "$CODE_UP_DIR/konrad-up-h-o-b"
  require_engine() { :; }
  eng_container_ls() { printf "konrad-up-h-o-a\nkonrad-up-h-o-b\n"; }
  code_up_running() { [[ "$1" != konrad-up-h-o-b ]]; }
  eng_stop_container() { echo "stop $1" >> "$HOME/calls"; }
  eng_rm_container_checked() { echo "rm $1" >> "$HOME/calls"; }
  env() { echo "start $*" >> "$HOME/calls"; }'

@test "code up --all: each marked repo starts as it was started" {
  k "$markers"'; code_up_all; cat "$HOME/calls"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"start KONRAD_MEMORY=12g _ code up --no-nested --capacity 2 https://h/o/a.git --verbose"* ]]
  [[ "$output" == *"start _ --profile p code up --kvm --capacity 4 https://h/o/b.git"* ]]
}

@test "code up --all, restart --all and down --all: --profile narrows them to its repos" {
  k "$markers"'; KONRAD_PROFILE=p; code_up_markers'
  [ "$output" = "$HOME/.local/state/konrad/code-up/konrad-up-h-o-b" ]
}

@test "code restart --all: stops, removes and starts each repo, and keeps its marker" {
  k "$markers"'; do_code_restart --all; cat "$HOME/calls"; ls "$CODE_UP_DIR"'
  [ "$status" -eq 0 ]
  # a is running: stopped, then removed; b is stopped already: only removed.
  [[ "$output" == *"stop konrad-up-h-o-a"*"rm konrad-up-h-o-a"*"start KONRAD_MEMORY=12g"*"rm konrad-up-h-o-b"*"start _ --profile p"* ]]
  [[ "$output" != *"stop konrad-up-h-o-b"* ]]
  [[ "$output" == *konrad-up-h-o-a*konrad-up-h-o-b ]]
}

@test "code restart <url>: only that repo; one that isn't up is refused" {
  k "$markers"'; do_code_restart https://h/o/a; cat "$HOME/calls"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"rm konrad-up-h-o-a"* && "$output" != *konrad-up-h-o-b* ]]
  k "$markers"'; do_code_restart https://h/o/c'
  [ "$status" -ne 0 ]
  [[ "$output" == *"isn't up"*"code up https://h/o/c"* ]]
  k "$markers"'; do_code_restart'
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage:"* ]]
}

@test "code restart: a container that can't be removed isn't started again, and fails the run" {
  k "$markers"'; eng_rm_container_checked() { [[ "$1" != konrad-up-h-o-a ]] || { echo "Error: busy"; return 1; }; }
     env() { echo "start $*"; }
     do_code_restart --all'
  [ "$status" -ne 0 ]
  [[ "$output" == *"couldn't remove konrad-up-h-o-a: Error: busy"* ]]
  [[ "$output" == *"couldn't restart: https://h/o/a"* ]]
  [[ "$output" != *"https://h/o/a.git --verbose"* ]]
  [[ "$output" == *"start _ --profile p code up"* ]]
}

@test "code down --all: stops every repo and forgets it" {
  k "$markers"'; do_code_down --all; cat "$HOME/calls"; ls -A "$CODE_UP_DIR"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"stop konrad-up-h-o-a"*"rm konrad-up-h-o-a"*"rm konrad-up-h-o-b"* ]]
  [[ "$output" != *start* ]]
  [ -z "$(ls -A "$HOME/.local/state/konrad/code-up")" ]
}

@test "code down --all and restart --all with nothing up say so" {
  k 'require_engine() { :; }; do_code_down --all'
  [ "$status" -eq 0 ]
  [[ "$output" == *"no repo is up"* ]]
  k 'require_engine() { :; }; do_code_restart --all'
  [ "$status" -eq 0 ]
  [[ "$output" == *"no repo should be up"* ]]
}

# --- argument parsing (the real script, run as a command) ----------------------------------

@test "update --check is gone, with a pointer to what replaces it" {
  run bash "$KONRAD" update --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"update --check was removed"* ]]
  [[ "$output" == *"konrad --version"* ]]
}

@test "update takes no other arguments" {
  run bash "$KONRAD" update now
  [ "$status" -eq 1 ]
  [[ "$output" == *"update: unknown argument 'now'"* ]]
}

@test "a modifier after a no-argument subcommand is refused with the fix" {
  run bash "$KONRAD" reset --no-firewall
  [ "$status" -eq 1 ]
  [[ "$output" == *"Modifier flags must come BEFORE the subcommand"* ]]
}

# --- konrad connect <id> ------------------------------------------------------

# sandbox_fixture '<composed config JSON>': the files connect_in_sandbox reads
# and writes in the sandbox, plus an `opencode` stub on PATH that prints its args.
sandbox_fixture() {
  export KONRAD_CONNECT_CONFIG="$BATS_TEST_TMPDIR/opencode.jsonc" KONRAD_CONNECT_AUTH="$BATS_TEST_TMPDIR/auth.json"
  printf '%s\n' "$1" >"$KONRAD_CONNECT_CONFIG"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\necho "opencode $*"\n' >"$BATS_TEST_TMPDIR/bin/opencode"
  chmod +x "$BATS_TEST_TMPDIR/bin/opencode"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}
ACME='{"provider":{"acme-llm":{"npm":"@ai-sdk/openai-compatible","options":{"baseURL":"https://llm.acme.example/v1"}}}}'

@test "connect_in_sandbox: a declared custom provider gets its key stored, others kept" {
  sandbox_fixture "$ACME"
  echo '{"openrouter":{"type":"api","key":"or-1"}}' >"$KONRAD_CONNECT_AUTH"
  k 'connect_in_sandbox acme-llm <<<"sk-secret"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"key for 'acme-llm' stored"* ]]
  [[ "$output" != *sk-secret* ]]
  [ "$(jq -c '."acme-llm"' "$KONRAD_CONNECT_AUTH")" = '{"type":"api","key":"sk-secret"}' ]
  [ "$(jq -r '.openrouter.key' "$KONRAD_CONNECT_AUTH")" = or-1 ]
  [ "$(stat -c %a "$KONRAD_CONNECT_AUTH")" = 600 ]
}

@test "connect_in_sandbox: the first key creates auth.json" {
  sandbox_fixture "$ACME"
  k 'connect_in_sandbox acme-llm <<<"sk-1"'
  [ "$status" -eq 0 ]
  [ "$(jq -r '."acme-llm".key' "$KONRAD_CONNECT_AUTH")" = sk-1 ]
}

@test "connect_in_sandbox: an empty key stores nothing" {
  sandbox_fixture "$ACME"
  k 'connect_in_sandbox acme-llm <<<""'
  [ "$status" -eq 1 ]
  [ ! -e "$KONRAD_CONNECT_AUTH" ]
}

@test "connect_in_sandbox: an undeclared id goes to opencode's own login" {
  sandbox_fixture '{"provider":{}}'
  k 'connect_in_sandbox openrouter'
  [ "$status" -eq 0 ]
  [ "$output" = "opencode auth login -p openrouter" ]
}

@test "connect_in_sandbox: a catalog provider declared without a baseURL keeps opencode's login" {
  sandbox_fixture '{"provider":{"anthropic":{"options":{"timeout":600000}}}}'
  k 'connect_in_sandbox anthropic'
  [ "$output" = "opencode auth login -p anthropic" ]
}

@test "connect_in_sandbox: --custom reports an undeclared id instead of logging in" {
  sandbox_fixture '{}'
  k 'connect_in_sandbox acme-llm --custom'
  [ "$status" -eq 3 ]
  [ -z "$output" ]
  [ ! -e "$KONRAD_CONNECT_AUTH" ]
}

@test "connect_in_sandbox: --custom on a declared id just stores the key" {
  sandbox_fixture "$ACME"
  k 'connect_in_sandbox acme-llm --custom <<<"sk-2"'
  [ "$status" -eq 0 ]
  [ "$(jq -r '."acme-llm".key' "$KONRAD_CONNECT_AUTH")" = sk-2 ]
}

@test "valid_provider_id: refuses anything but letters, digits, - and _" {
  k 'valid_provider_id acme-llm_2'
  [ "$status" -eq 0 ]
  k 'valid_provider_id "acme;rm"'
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid provider id"* ]]
}
