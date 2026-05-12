#!/usr/bin/env bash
# konrad entrypoint: keep auth.json on a podman-managed volume so it
# never ends up on the host filesystem (and can't be committed by
# accident), while sessions/sqlite stay in the bind-mounted .agent/.
set -euo pipefail

OPENCODE_DATA=/home/node/.local/share/opencode
SECRETS=/home/node/.opencode-secrets

mkdir -p "$OPENCODE_DATA" "$SECRETS"

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

# Symlink so opencode transparently reads/writes the volume copy.
if [[ ! -L "$OPENCODE_DATA/auth.json" ]]; then
  ln -sf "$SECRETS/auth.json" "$OPENCODE_DATA/auth.json"
fi

exec "$@"
