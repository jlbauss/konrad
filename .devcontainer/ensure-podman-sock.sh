#!/usr/bin/env sh
# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
#
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
# Runs on Linux and macOS hosts (POSIX sh). Both branches are verified on real
# hardware (macOS: 2026-06-10, rootful-connection route).
#
# It also installs the podman-vscode.sh shim to a STABLE host path
# (~/.local/bin/podman-vscode.sh) so VS Code's `dev.containers.dockerPath` can
# point there once and keep working across konrad and any config-layer repo
# that reuses this dev container, without changing the setting per project.
# FIRST-TIME BOOTSTRAP (per machine): VS Code probes dockerPath ("Check Docker
# is running") BEFORE it runs initializeCommand, so on a fresh machine where the
# shim isn't installed yet the probe fails with ENOENT and the container never
# starts. Run this script once by hand before the very first container open —
# `sh .devcontainer/ensure-podman-sock.sh` — and from then on it keeps the shim
# refreshed automatically on every open.

set -eu

script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"

# Install the dockerPath shim to a stable host path (see header). Plain cp — the
# shim is small and refreshing it on every open keeps it in sync with the repo.
mkdir -p "$HOME/.local/bin"
cp "$script_dir/podman-vscode.sh" "$HOME/.local/bin/podman-vscode.sh"
chmod +x "$HOME/.local/bin/podman-vscode.sh"

cache_dir="$script_dir/.cache"
link="$cache_dir/podman-host.sock"
mkdir -p "$cache_dir"

# Guarantee the host config dir exists so devcontainer.json's bind mount of it
# resolves at container-create time (a missing bind source hard-fails create).
# Create only the PARENT, never .../user — pre-creating user/ would make
# bin/konrad's migrate_flat_config think the new layout is already in place and
# skip migrating a contributor's legacy flat config. Self-testing mounts these
# layers into the runtime container (see bin/konrad podman_run, CONTRIBUTING.md).
mkdir -p "${HOME}/.config/konrad"

real=""
case "$(uname -s)" in
  Darwin)
    # macOS: podman runs inside a VM (libkrun/qemu) and the dev container runs
    # inside that same VM. The VM's ROOTLESS socket is a dead end from a nested
    # container (unmapped-uid wall, diagnosed 2026-06-05 — see git history),
    # but the machine also ships a ROOTFUL daemon whose socket IS reachable
    # when the dev container itself is created via the rootful connection with
    # explicit uid/gid maps — that's what .devcontainer/podman-vscode.sh does
    # (one-time dockerPath wire-up: see that file / CONTRIBUTING.md).
    #
    # The path below is VM-INTERNAL: it does not exist on the Mac, so no -S
    # check here. The workspace is virtiofs-shared into the VM at an identical
    # path, so the symlink resolves daemon-side at mount time. Verified on
    # real hardware 2026-06-10. Gated on a running machine so a podman-less
    # Mac still degrades to /dev/null; without the podman-vscode.sh wire-up
    # the container comes up rootless and podman calls against the root-owned
    # socket fail cleanly (self-testing off), as before.
    if podman machine inspect --format '{{.State}}' 2>/dev/null | grep -q running; then
      ln -sfn /run/podman/podman.sock "$link"
      exit 0
    fi
    ;;
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
