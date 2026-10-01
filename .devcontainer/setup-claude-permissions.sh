#!/bin/sh
# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# postCreateCommand: enable Claude Code's bypassPermissions mode, but ONLY
# inside this dev container — and invisibly to the host.
#
# We write the USER-level settings ($HOME/.claude/settings.json), not the
# project-level .claude/settings.local.json. The project dir is a host bind
# mount, so a file there is physically on the host disk and a bare-host `claude`
# run in the same directory would read it. $HOME/.claude is backed by the
# container-only named volume (devcontainer.json mounts), so the setting lives
# nowhere on the host tree and a host run reads its own $HOME/.claude instead.
# defaultMode is honored at user scope and wins when neither project nor local
# settings set it (which they must not — keep it out of committed settings).
#
# The disposable container plus the committed deny/ask lists are the security
# boundary (CLAUDE.md → Permission posture). Two guards live here, not in the
# committed lists, because `konrad code` reads the same repo settings and needs
# neither: `git push` is denied (this container pushes with the host's
# credentials; `konrad code` pushes a feature branch with a project token by
# design), and `podman run` / `podman system prune` stay `ask` (here podman is
# the HOST socket, where `podman run -v …` escapes the container; in `konrad
# code` it's the agent's own nested engine).
#
# Idempotent and non-destructive: merges these keys into whatever else the file
# holds, never replaces it.
set -eu

f="$HOME/.claude/settings.json"
mkdir -p "$HOME/.claude"
[ -s "$f" ] || printf '{}\n' > "$f"

tmp=$(mktemp "${f}.XXXXXX")
jq '.permissions.defaultMode = "bypassPermissions"
    | .permissions.deny = ((.permissions.deny // []) + ["Bash(git push:*)"] | unique)
    | .permissions.ask = ((.permissions.ask // []) + ["Bash(podman run:*)", "Bash(podman system prune:*)"] | unique)' "$f" > "$tmp"
mv "$tmp" "$f"

echo "claude: bypassPermissions enabled, git push denied, podman run asks, for this dev container (container-only $f)"
