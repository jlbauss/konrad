#!/usr/bin/env bash
# konrad entrypoint. Runs before opencode (or whatever the user invoked)
# on every container start. Responsibilities:
#   1. Compose opencode's runtime config by deep-merging konrad's baked
#      defaults with the user's optional override.
#   2. Layer in the user's own agents / skills / AGENTS.md if they ship any.
#   3. Keep auth.json on a podman-managed volume (via a symlink) so it
#      never lands on the host filesystem.
set -euo pipefail

OPENCODE_CFG=/home/node/.config/opencode
OPENCODE_DATA=/home/node/.local/share/opencode
SECRETS=/home/node/.opencode-secrets

USER_CFG=/home/node/.config/konrad             # everything below comes from the host
KONRAD_BAKED=/etc/konrad                       # everything below was shipped in the image

mkdir -p "$OPENCODE_CFG" "$OPENCODE_DATA" "$SECRETS"

# ── 1. Compose opencode.jsonc (baked defaults + optional user override) ──────
TARGET_JSONC="$OPENCODE_CFG/opencode.jsonc"
if [[ -f "$USER_CFG/opencode.jsonc" ]]; then
  echo "[konrad] merging user opencode.jsonc with baked defaults" >&2
  node "$KONRAD_BAKED/merge-config.js" \
    "$KONRAD_BAKED/opencode-defaults.jsonc" \
    "$USER_CFG/opencode.jsonc" \
    > "$TARGET_JSONC"
else
  # No user override — use baked defaults verbatim (preserves comments).
  cp "$KONRAD_BAKED/opencode-defaults.jsonc" "$TARGET_JSONC"
fi

# ── 2. Layer in user-shipped agents / skills / AGENTS.md ─────────────────────
# Each is optional. If the user hasn't provided one, do nothing.
# `cp -r` here means user files OVERWRITE baked ones on name collision
# (e.g. user-shipped `agents/konrad.md` replaces ours). That's intentional:
# this is the "I want to run my own konrad agent" escape hatch.

if [[ -d "$USER_CFG/agents" ]]; then
  cp -r "$USER_CFG/agents/." "$OPENCODE_CFG/agents/"
fi

if [[ -d "$USER_CFG/skills" ]]; then
  cp -r "$USER_CFG/skills/." "$OPENCODE_CFG/skills/"
fi

if [[ -f "$USER_CFG/AGENTS.md" ]]; then
  cp "$USER_CFG/AGENTS.md" "$OPENCODE_CFG/AGENTS.md"
fi

# ── 3. auth.json on a named volume (unchanged from previous behaviour) ───────
# Migrate a pre-existing real auth.json (from before this split, or
# from a user who manually placed one) into the secrets volume once.
if [[ -f "$OPENCODE_DATA/auth.json" && ! -L "$OPENCODE_DATA/auth.json" ]]; then
  if [[ -e "$SECRETS/auth.json" ]]; then
    echo "[konrad] auth.json already in secrets volume; removing stray copy from .agent/" >&2
    rm "$OPENCODE_DATA/auth.json"
  else
    echo "[konrad] migrating auth.json into the secrets volume (one-time)" >&2
    mv "$OPENCODE_DATA/auth.json" "$SECRETS/auth.json"
  fi
fi

if [[ ! -L "$OPENCODE_DATA/auth.json" ]]; then
  ln -sf "$SECRETS/auth.json" "$OPENCODE_DATA/auth.json"
fi

exec "$@"
