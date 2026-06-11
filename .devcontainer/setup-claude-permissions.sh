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
# boundary (CLAUDE.md → Permission posture); `podman run` stays `ask` even here.
#
# Idempotent and non-destructive: merges the one key into whatever else the file
# holds, never replaces it.
set -eu

f="$HOME/.claude/settings.json"
mkdir -p "$HOME/.claude"
[ -s "$f" ] || printf '{}\n' > "$f"

tmp=$(mktemp "${f}.XXXXXX")
jq '.permissions.defaultMode = "bypassPermissions"' "$f" > "$tmp"
mv "$tmp" "$f"

echo "claude: bypassPermissions enabled for this dev container (container-only $f)"
