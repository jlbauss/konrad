#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Probe: can parallel `konrad code --nested` sessions share one repo's nested
# image store? Podman only (on apple/container the store is a block volume one
# VM can attach, so parallel sessions there get a store each — see do_code).
# Runs on a host or inside `konrad code --nested` itself:
#
#   ./scripts/probe-shared-store.sh              # all three modes, asserted
#   PROBE_IMAGE=localhost/konrad:local ./scripts/probe-shared-store.sh
#
# Two "session" containers of the konrad image mount ONE store volume at the
# real path, while /tmp (libpod's run root, tmpdir, pause process) and /dev/shm
# (its lock table) stay per container — what two real sessions have. Each mode
# runs the same steps: A starts a container, B's first podman command, both
# start more, parallel image commits, B's session ends and a fresh one starts,
# B prunes while A runs, then `podman system check`.
#
#   baseline     A and B both inside session container A (two shells in one
#                session) — must pass; proves the harness itself is sound.
#   shared-db    today's config across two containers: libpod's database sits
#                in the shared store. Expected to FAIL — B's first command
#                "refreshes" the db as after a reboot, resetting A's running
#                containers, and the two lock tables hand out the same locks.
#   per-session  the konrad-code-entrypoint.sh config: each non-primary session
#                keeps libpod's static dir and volumes under the store's
#                sessions/<name>/ — must pass, with images still shared.
#
# Knobs: PROBE_IMAGE (an image with konrad's nested podman). The session
# containers use a slightly smaller subordinate range so this also runs one
# level down, inside konrad code. Needs only podman; changes nothing in konrad.
set -uo pipefail

img="${PROBE_IMAGE:-ghcr.io/jlbauss/konrad:latest}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
printf 'node:1:999\nnode:1001:60000\n' > "$tmp/subid"
chmod 644 "$tmp/subid"
fails=0

probe() {  # probe <mode> <expect: pass|fail>
  local mode="$1" expect="$2" vol="konrad-store-probe-$1" bad=0
  session() {  # session <A|B> — a fresh session container, like a --rm run
    local c="konrad-store-probe-$mode-$1" conf=""
    podman rm -f -t 0 "$c" >/dev/null 2>&1
    podman run -d --name "$c" --user node \
      --device /dev/net/tun --cap-add SYS_CHROOT --cap-add SETUID --cap-add SETGID \
      --security-opt 'unmask=/proc/*' --security-opt label=disable \
      -v "$tmp/subid:/etc/subuid:ro" -v "$tmp/subid:/etc/subgid:ro" \
      -v "$vol:/var/lib/konrad-containers" \
      --entrypoint sleep "$img" infinity >/dev/null
    # The entrypoint's per-session config, verbatim in effect.
    [[ "$mode" == per-session ]] && conf="/var/lib/konrad-containers/sessions/$1" \
      && podman exec "$c" sh -c "mkdir -p $conf && printf '[engine]\nstatic_dir = \"$conf/libpod\"\nvolume_path = \"$conf/volumes\"\n' > /tmp/s.conf"
    return 0
  }
  p() {  # p <A|B> podman-args… — that session's inner podman
    local s="$1"; shift
    [[ "$mode" == baseline ]] && s=A
    local -a env=()
    [[ "$mode" == per-session ]] && env=(-e CONTAINERS_CONF_OVERRIDE=/tmp/s.conf)
    podman exec ${env[@]+"${env[@]}"} "konrad-store-probe-$mode-$s" podman "$@"
  }
  st() { p "$1" ps -a --format '{{.Names}}={{.State}}' 2>&1 | sort | tr '\n' ' '; }
  want() {  # want <label> <cmd…> — a step that must succeed
    if "${@:2}" >/dev/null 2>&1; then echo "  ok    $1"; else echo "  FAIL  $1"; bad=$((bad + 1)); fi
  }
  running() { [[ "$(p "$1" inspect -f '{{.State.Status}}' "$2" 2>/dev/null)" == running ]]; }
  locks_clean() { ! p A system locks 2>&1 | grep -q '^Lock conflicts have been detected'; }

  printf '\n== %s (expected to %s)\n' "$mode" "$expect"
  podman volume rm -f "$vol" >/dev/null 2>&1
  session A; session B
  want "A pulls alpine and starts a1" p A run -d --name a1 docker.io/library/alpine:latest sleep 600
  echo "        B's first command sees: $(st B)"
  want "a1 still running after B's first command" running A a1
  want "A can exec into a1" p A exec a1 true
  want "B starts b1" p B run -d --name b1 docker.io/library/alpine:latest sleep 600
  want "A starts a3" p A run -d --name a3 docker.io/library/alpine:latest sleep 600
  want "no lock conflicts" locks_clean
  p A commit -q a3 probe/a >/dev/null 2>&1 & local ja=$!
  p B commit -q b1 probe/b >/dev/null 2>&1 & local jb=$!
  want "parallel commit from A" wait "$ja"
  want "parallel commit from B" wait "$jb"
  want "B sees the image A built" p B image exists localhost/probe/a
  session B
  echo "        B's next session sees: $(st B)"
  want "B's next session runs a container" p B run --rm docker.io/library/alpine:latest true
  want "a1 still running after B's next session" running A a1
  p B system prune -af >/dev/null 2>&1
  want "a1 still running after B prunes" running A a1
  want "A still runs containers after B prunes" p A run --rm docker.io/library/alpine:latest true
  want "podman system check is clean" p A system check
  podman rm -f -t 0 "konrad-store-probe-$mode-A" "konrad-store-probe-$mode-B" >/dev/null 2>&1
  podman volume rm -f "$vol" >/dev/null 2>&1

  if [[ "$expect" == pass && "$bad" -gt 0 ]] || [[ "$expect" == fail && "$bad" -eq 0 ]]; then
    echo "  => UNEXPECTED: $mode had $bad failing step(s), expected to $expect"; fails=$((fails + 1))
  else
    echo "  => as expected ($bad failing step(s))"
  fi
}

probe baseline pass
probe shared-db fail
probe per-session pass
echo
if (( fails == 0 )); then
  echo "probe-shared-store: all modes as expected"
else
  echo "probe-shared-store: $fails mode(s) off"; exit 1
fi
