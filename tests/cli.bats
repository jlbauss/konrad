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
