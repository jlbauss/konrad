#!/usr/bin/env sh
# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# VS Code Dev Containers podman shim — enables runtime self-testing on macOS.
#
# Wire-up (one-time, macOS only) in the VS Code USER settings JSON:
#
#     "dev.containers.dockerPath": "/absolute/path/to/konrad/.devcontainer/podman-vscode.sh"
#
# Linux contributors don't set dockerPath at all (the extension calls podman
# directly); if this shim runs on Linux anyway it's a transparent pass-through.
#
# Why this exists (macOS): the dev container runs INSIDE the podman-machine VM,
# and the VM's rootless daemon socket is unreachable from a nested rootless
# container (unmapped-uid wall — diagnosed 2026-06-05, see git history). The
# machine also ships a ROOTFUL daemon + connection out of the box, and a
# container created by THAT daemon can reach its socket — so this shim routes
# only the Dev Containers extension to it. The machine's DEFAULT connection
# stays rootless: day-to-day `podman` / `konrad` on the Mac is untouched (this
# is deliberately NOT `podman machine set --rootful`).
#
# Three rootful deltas, all verified on real hardware 2026-06-10, handled by
# rewriting the container-create args:
#   - `--userns=keep-id…` (rootless-only semantics) degrades to an identity
#     map under a rootful daemon, while virtiofs presents workspace files
#     with their raw Mac uid/gid — so node(1000) must be mapped to the Mac
#     user's ids explicitly for /workspace to stay writable.
#   - The rootful API socket is root:root mode 660; a supplementary group
#     mapped to the VM's root gid (container gid 999 below) grants access.
#     (If `podman exec` sessions ever lose that supplementary group, swap the
#     999↔1000 gidmap lines so host gid 0 becomes node's PRIMARY group.)
#   - SELinux is Enforcing in the machine VM and denies a container context
#     access to the socket's label → label=disable.
#
# KONRAD_DAEMON_ROOTFUL / KONRAD_REMOTE_UID / KONRAD_REMOTE_GID tell bin/konrad
# (inside the dev container) to apply the same mapping treatment to the nested
# konrad runtime container — see podman_run() in bin/konrad.

set -eu

[ "$(uname -s)" = "Darwin" ] || exec podman "$@"

uid="$(id -u)"
gid="$(id -g)"

# Rebuild the arg list: the keep-id flag from devcontainer.json runArgs only
# appears on container create/run — wherever it shows up, substitute the
# rootful mapping set in place. Everything else passes through verbatim.
for arg in "$@"; do
  shift
  case "$arg" in
    --userns=keep-id*)
      set -- "$@" \
        --security-opt label=disable \
        --uidmap 0:100000:999 --uidmap 999:0:1 \
        --uidmap "1000:$uid:1" --uidmap 1001:101001:64535 \
        --gidmap 0:100000:999 --gidmap 999:0:1 \
        --gidmap "1000:$gid:1" --gidmap 1001:101001:64535 \
        --group-add 999 \
        --env KONRAD_DAEMON_ROOTFUL=1 \
        --env "KONRAD_REMOTE_UID=$uid" \
        --env "KONRAD_REMOTE_GID=$gid"
      ;;
    *)
      set -- "$@" "$arg"
      ;;
  esac
done

exec podman --connection podman-machine-default-root "$@"
