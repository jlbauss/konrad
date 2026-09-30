# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
# shellcheck shell=bash
#
# Shared privilege-drop helper for konrad's root-prelude entrypoints:
#   - image/entrypoint.sh           — the agent's egress seal (blackhole the
#                                      host-gateway route, then drop),
#   - image/konrad-proxy-entrypoint.sh — the proxy's local-model host alias
#                                      (write /etc/hosts, then drop), and
#   - image/konrad-code-entrypoint.sh  — the konrad code host/LAN seal.
# Each starts the container as root ONLY to perform one privileged setup step,
# then re-execs the rest of the entrypoint as the unprivileged node user.
# Sourced, never executed. One canonical implementation so the
# security-sensitive drop logic lives in exactly one place.

# Drop root → node and exec "$@" with the capability bounding set cleared, so the
# re-executed process can never regain a capability the prelude used. Prefers
# exec-replacing tools (setpriv, gosu) over runuser (which forks); setpriv ships
# in the image (verified on apple/container; smoke-asserted). HOME/USER/LOGNAME
# are forced because starting the container as uid 0 leaves them pointing at
# /root, which would send opencode (and the proxy's tooling) to the wrong home.
# Fails closed: if no drop tool is found, abort rather than continue as root.
#
# `exec_as_node --keep-caps setuid,setgid cmd…` keeps exactly those in the
# bounding set instead (konrad code --nested: the file-capability uid mappers
# need them). Only setpriv can do that, so the fallbacks refuse it.
exec_as_node() {
  local bounding=-all keep
  if [[ "${1:-}" == --keep-caps ]]; then
    keep="$2"; shift 2
    bounding="-all,+${keep//,/,+}"
  fi
  export HOME=/home/node USER=node LOGNAME=node
  if command -v setpriv >/dev/null 2>&1; then
    exec setpriv --reuid 1000 --regid 1000 --init-groups --bounding-set="$bounding" -- "$@"
  elif [[ -n "${keep:-}" ]]; then
    printf '[konrad] FATAL: keeping capabilities needs setpriv — refusing to run\n' >&2
    exit 1
  elif command -v gosu >/dev/null 2>&1; then
    exec gosu node "$@"
  elif command -v runuser >/dev/null 2>&1; then
    exec runuser -u node -- "$@"
  fi
  printf '[konrad] FATAL: no privilege-drop tool (setpriv/gosu/runuser) in image — refusing to run as root\n' >&2
  exit 1
}
