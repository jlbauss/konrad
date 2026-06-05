#!/usr/bin/env sh
# Host-side initializeCommand for the konrad dev container.
#
# Normalizes the host's rootless podman socket into a STABLE, always-present
# path that devcontainer.json can mount unconditionally:
#
#     .devcontainer/.cache/podman-host.sock  ->  <real podman socket>  (found)
#                                            ->  /dev/null              (fallback)
#
# Why this exists: the dev container mounts the host podman socket so the agent
# working ON konrad can self-test the runtime image (see CLAUDE.md). A long-form
# `type=bind` mount requires its SOURCE to exist, or container creation
# hard-fails. The real socket path is OS-specific (and absent entirely on a host
# without podman, or a Linux host that never ran `systemctl --user enable --now
# podman.socket`). So we resolve it here — on the host, before the container is
# created, since initializeCommand runs first — and always leave a resolvable
# symlink behind. No usable socket -> symlink to /dev/null, so the container
# still comes up and podman calls simply fail (graceful "no self-testing")
# instead of blocking the container from starting at all.
#
# Runs on Linux and macOS hosts (POSIX sh). The macOS branch is best-effort and
# unverified on real hardware — see the macOS self-testing item in ROADMAP.md.

set -eu

cache_dir="$(cd -- "$(dirname -- "$0")" && pwd)/.cache"
link="$cache_dir/podman-host.sock"
mkdir -p "$cache_dir"

real=""
case "$(uname -s)" in
  Darwin)
    # macOS: podman runs inside a VM (libkrun/qemu) and the dev container runs
    # inside that same VM. The host-side socket from `podman machine inspect`
    # lives at a Mac path (e.g. /var/folders/.../T/podman/...api.sock) that does
    # NOT exist inside the VM, so bind-mounting a symlink to it would resolve to
    # a missing in-VM target and could break container creation. We therefore
    # leave `real` empty: the mount falls back to /dev/null and the container
    # starts cleanly with self-testing disabled. Wiring a VM-reachable socket
    # for real macOS self-testing is a separate, open task (see ROADMAP.md) —
    # it needs the VM-INTERNAL socket, not this host-side forwarding one.
    : ;;
  *)
    # Linux rootless socket. XDG_RUNTIME_DIR is the canonical location; fall
    # back to the conventional /run/user/<uid> when it's unset.
    real="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/podman/podman.sock"
    ;;
esac

if [ -n "$real" ] && [ -S "$real" ]; then
  ln -sfn "$real" "$link"
else
  # No usable socket — keep the mount source resolvable so the container still
  # starts; podman calls against /dev/null fail cleanly (no self-testing).
  ln -sfn /dev/null "$link"
fi
