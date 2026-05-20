#!/usr/bin/env bash
# Install the host-side SSH-agent bridge that the konrad dev container
# depends on for `git push` over SSH remotes.
#
# Background: VS Code's automatic SSH_AUTH_SOCK forwarding into Dev
# Containers is unreliable on macOS + rootless podman, because macOS's
# launchd-managed agent socket (/var/run/com.apple.launchd.*/Listeners)
# lives in the host userspace and cannot be bind-mounted through
# libkrun. Workaround: a LaunchAgent runs `socat` to expose that agent
# at ~/.ssh/podman-agent.sock — a regular Unix socket that virtiofs CAN
# pass through. .devcontainer/devcontainer.json bind-mounts it into the
# container at /tmp/ssh-auth-sock.
#
# Run once after cloning the repo on a new macOS machine. Idempotent.
# Linux hosts don't need this — VS Code's auto-forwarding works there.
set -euo pipefail

LABEL="dev.konrad.ssh-agent-bridge"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLIST_SRC="${SCRIPT_DIR}/host-ssh-bridge.plist"
PLIST_DST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
BRIDGE_SOCK="${HOME}/.ssh/podman-agent.sock"

say() { printf 'konrad-host-ssh-bridge: %s\n' "$*"; }
die() { printf 'konrad-host-ssh-bridge: %s\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] \
  || die "macOS only — VS Code's built-in SSH_AUTH_SOCK forwarding works on Linux"

[[ -f "$PLIST_SRC" ]] || die "expected plist template at $PLIST_SRC (is the repo intact?)"

# 1. socat — required by the LaunchAgent
if ! command -v socat >/dev/null 2>&1; then
  command -v brew >/dev/null 2>&1 \
    || die "neither socat nor Homebrew found; install one of them first"
  say "installing socat via Homebrew"
  brew install socat
fi

# 2. one-time migration: an earlier prototype used a placeholder label.
#    If it's still loaded, evict it before installing the real one.
OLD_LABEL="com.user.ssh-agent-bridge"
if launchctl print "gui/$(id -u)/${OLD_LABEL}" >/dev/null 2>&1; then
  say "removing legacy LaunchAgent (${OLD_LABEL})"
  launchctl bootout "gui/$(id -u)/${OLD_LABEL}" 2>/dev/null || true
  rm -f "${HOME}/Library/LaunchAgents/${OLD_LABEL}.plist"
fi

# 3. drop the plist into LaunchAgents/
mkdir -p "$(dirname "$PLIST_DST")"
cp "$PLIST_SRC" "$PLIST_DST"
say "installed plist at $PLIST_DST"

# 4. (re)load — bootout first so edits to an already-loaded plist are picked up
if launchctl print "gui/$(id -u)/${LABEL}" >/dev/null 2>&1; then
  launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true
fi
launchctl bootstrap "gui/$(id -u)" "$PLIST_DST"
say "loaded LaunchAgent: ${LABEL}"

# 5. verify the bridge is up and the host agent has at least one key
sleep 1
[[ -S "$BRIDGE_SOCK" ]] \
  || die "bridge socket did not appear at $BRIDGE_SOCK — see /tmp/ssh-agent-bridge.log"

if SSH_AUTH_SOCK="$BRIDGE_SOCK" ssh-add -l >/dev/null 2>&1; then
  say "bridge OK — host SSH agent reachable via $BRIDGE_SOCK"
else
  say "warning: bridge socket exists but no keys reachable through it"
  say "  if your agent is empty, run: ssh-add ~/.ssh/id_ed25519"
fi

say "done — next: 'Dev Containers: Rebuild Container' in VS Code"
