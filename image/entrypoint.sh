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

KONRAD_DEBUG="${KONRAD_DEBUG:-0}"

say() { printf '[konrad container] %s\n' "$*" >&2; }
dbg() {
  [[ "$KONRAD_DEBUG" != "1" ]] && return 0
  printf '[konrad container debug %s] %s\n' "$(date +%H:%M:%S.%3N)" "$*" >&2
}

dbg "entrypoint start"

mkdir -p "$OPENCODE_CFG" "$OPENCODE_DATA" "$SECRETS"
dbg "mkdir done"

# ── 1. Compose opencode.jsonc (baked defaults + runtime override + user override) ──
# Three layers, merged in order so the latter wins on conflicts:
#   1. /etc/konrad/opencode-defaults.jsonc          (baked into image)
#   2. /tmp/konrad-runtime-override.jsonc           (generated below from
#                                                    KONRAD_PROVIDER_EXCLUDES)
#   3. ~/.config/konrad/opencode.jsonc              (bind-mounted from host)
TARGET_JSONC="$OPENCODE_CFG/opencode.jsonc"
RUNTIME_OVERRIDE=""

# Build the runtime override if the CLI passed a non-empty exclude list.
# The exclude list adds providers that aren't reachable on the host to
# the discovery plugin's providers.exclude, so the plugin doesn't waste
# 3 seconds per missing provider.
if [[ -n "${KONRAD_PROVIDER_EXCLUDES:-}" ]]; then
  RUNTIME_OVERRIDE=/tmp/konrad-runtime-override.jsonc
  # Convert the CSV from KONRAD_PROVIDER_EXCLUDES into a JSON string array.
  # Always include "lmstudio" since the baked default excludes it for the
  # embedding-modality bug and we want both lists merged.
  IFS=',' read -r -a _excludes <<< "lmstudio,${KONRAD_PROVIDER_EXCLUDES}"
  _list=""
  for _name in "${_excludes[@]}"; do
    [[ -z "$_name" ]] && continue
    [[ -n "$_list" ]] && _list="${_list}, "
    _list="${_list}\"${_name}\""
  done
  cat > "$RUNTIME_OVERRIDE" <<EOF
{
  "plugin": [
    ["opencode-models-discovery@0.8.0", { "providers": { "exclude": [${_list}] } }]
  ]
}
EOF
  say "runtime: excluding unreachable providers from discovery (${KONRAD_PROVIDER_EXCLUDES})"
fi

INTERMEDIATE="$KONRAD_BAKED/opencode-defaults.jsonc"
if [[ -n "$RUNTIME_OVERRIDE" ]]; then
  node "$KONRAD_BAKED/merge-config.js" \
    "$KONRAD_BAKED/opencode-defaults.jsonc" \
    "$RUNTIME_OVERRIDE" \
    > /tmp/konrad-intermediate.jsonc
  INTERMEDIATE=/tmp/konrad-intermediate.jsonc
fi

if [[ -f "$USER_CFG/opencode.jsonc" ]]; then
  say "composing config: baked + runtime + your override"
  node "$KONRAD_BAKED/merge-config.js" \
    "$INTERMEDIATE" \
    "$USER_CFG/opencode.jsonc" \
    > "$TARGET_JSONC"
elif [[ -n "$RUNTIME_OVERRIDE" ]]; then
  say "composing config: baked + runtime (no user override found)"
  cp "$INTERMEDIATE" "$TARGET_JSONC"
else
  say "composing config: baked defaults (no overrides)"
  cp "$KONRAD_BAKED/opencode-defaults.jsonc" "$TARGET_JSONC"
fi
dbg "config composed at $TARGET_JSONC"

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
dbg "user content layered in"

# ── 3. auth.json on a named volume ───────────────────────────────────────────
# Migrate a real auth.json sitting in the workspace's .agent/opencode/ data
# dir (i.e. not yet on the secrets volume) into the secrets volume once, then
# symlink the data-dir path back at the volume so opencode keeps finding it.
if [[ -f "$OPENCODE_DATA/auth.json" && ! -L "$OPENCODE_DATA/auth.json" ]]; then
  if [[ -e "$SECRETS/auth.json" ]]; then
    say "auth.json already in secrets volume; removing stray copy from .agent/"
    rm "$OPENCODE_DATA/auth.json"
  else
    say "migrating auth.json into the secrets volume (one-time)"
    mv "$OPENCODE_DATA/auth.json" "$SECRETS/auth.json"
  fi
fi

if [[ ! -L "$OPENCODE_DATA/auth.json" ]]; then
  ln -sf "$SECRETS/auth.json" "$OPENCODE_DATA/auth.json"
fi
dbg "auth.json symlink ready"

dbg "entrypoint done — about to exec: $*"

# opencode writes a fresh, timestamped INFO-level log file under
# ~/.local/share/opencode/log/ on every launch, with per-line +Xms deltas
# (the structure that makes "what took 2 seconds" easy to spot). Inside
# konrad that path is bind-mounted to the host workspace, so the same
# file is visible there at .agent/opencode/log/<timestamp>.log — easy
# to tail in another shell, or via `konrad logs`.
say "opencode logs: .agent/opencode/log/ in this workspace"
say "starting opencode…"

# Debug mode: ask Bun to print every fetch/http call to fd 2. This catches
# slow network round-trips that opencode's own logger doesn't surface
# (e.g. the models.dev catalog fetch, plugin install probes).
# We don't bother with OPENCODE_LOG_LEVEL or DEBUG=opencode:* — neither
# exists in the current opencode source; the file log already gives us
# what we need.
if [[ "$KONRAD_DEBUG" == "1" ]]; then
  export BUN_CONFIG_VERBOSE_FETCH=true
  dbg "BUN_CONFIG_VERBOSE_FETCH=true"
fi

exec "$@"
