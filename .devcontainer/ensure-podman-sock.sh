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
    # inside that same VM, so self-testing has no reachable socket to mount and
    # we leave `real` empty -> /dev/null (container starts, self-testing off).
    # Two routes were tried and ruled out on real hardware (2026-06-05):
    #   - host-side socket (`podman machine inspect`): a Mac path absent inside
    #     the VM, so the mount can't resolve;
    #   - VM-internal socket (/run/user/<uid>/podman/podman.sock): the mount
    #     RESOLVES, but it's owned by the VM user at a uid unmapped in the dev
    #     container's rootless keep-id namespace -> EACCES, and an idmapped
    #     bind mount is rejected (mount_setattr: Operation not permitted).
    # The only fixes left are a VM-side TCP service or socket proxy — custom
    # maintenance machinery, deferred. Full write-up in ROADMAP.md.
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
