#!/usr/bin/env bash
# konrad entrypoint. Runs before opencode (or whatever the user invoked)
# on every container start. Responsibilities:
#   1. Compose opencode's runtime config by deep-merging konrad's baked
#      defaults with the user's optional override.
#   2. Layer in the user's own agents / skills / AGENTS.md if they ship any.
#   3. Keep auth.json on a podman-managed volume (via a symlink) so it
#      never lands on the host filesystem.
#   4. Bootstrap and auto-prune the workspace's .agent/ working dirs.
#   5. Write a per-session sidecar into the central log dir recording the
#      host workspace path (since opencode itself only sees /workspace).
set -euo pipefail

OPENCODE_CFG=/home/node/.config/opencode
OPENCODE_DATA=/home/node/.local/share/opencode
OPENCODE_LOG_DIR="$OPENCODE_DATA/log"             # bound to host XDG state from bin/konrad
SECRETS=/home/node/.opencode-secrets
WORKSPACE_AGENT=/workspace/.agent                 # the agent's working-state root

USER_CFG=/home/node/.config/konrad             # everything below comes from the host
KONRAD_BAKED=/etc/konrad                       # everything below was shipped in the image

KONRAD_DEBUG="${KONRAD_DEBUG:-0}"
KONRAD_HOST_WORKSPACE="${KONRAD_HOST_WORKSPACE:-(unknown — KONRAD_HOST_WORKSPACE not set)}"
KONRAD_HOST_LOG_DIR="${KONRAD_HOST_LOG_DIR:-(unknown — KONRAD_HOST_LOG_DIR not set)}"

say() { printf '[konrad container] %s\n' "$*" >&2; }
warn() { printf '[konrad container] warning: %s\n' "$*" >&2; }
dbg() {
  [[ "$KONRAD_DEBUG" != "1" ]] && return 0
  printf '[konrad container debug %s] %s\n' "$(date +%H:%M:%S.%3N)" "$*" >&2
}

dbg "entrypoint start"

mkdir -p "$OPENCODE_CFG" "$OPENCODE_DATA" "$OPENCODE_LOG_DIR" "$SECRETS"
dbg "mkdir done"

# ── 1. Compose opencode.jsonc (baked defaults + optional user override) ──
# Two layers, merged in order so the user wins on conflicts:
#   1. /etc/konrad/opencode-defaults.jsonc          (baked into image)
#   2. ~/.config/konrad/opencode.jsonc              (bind-mounted from host)
TARGET_JSONC="$OPENCODE_CFG/opencode.jsonc"

if [[ -f "$USER_CFG/opencode.jsonc" ]]; then
  say "composing config: baked + your override"
  node "$KONRAD_BAKED/merge-config.js" \
    "$KONRAD_BAKED/opencode-defaults.jsonc" \
    "$USER_CFG/opencode.jsonc" \
    > "$TARGET_JSONC"
else
  say "composing config: baked defaults (no user override)"
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

# ── 2b. Font overlay ─────────────────────────────────────────────────────────
# Anything the user drops into ~/.config/konrad/fonts/ on the host shows up
# at $USER_CFG/fonts in the container (bind-mounted by bin/konrad). Symlink
# it into ~/.local/share/fonts/, which fontconfig watches by default, and
# refresh the cache. Symlink rather than copy so adding a font on the host
# is picked up on the next launch without an extra step.
USER_FONTS_DIR=/home/node/.local/share/fonts/konrad-user
USER_FONT_COUNT=0
if [[ -d "$USER_CFG/fonts" ]]; then
  USER_FONT_COUNT=$(find "$USER_CFG/fonts" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null | wc -l)
fi
if (( USER_FONT_COUNT > 0 )); then
  mkdir -p /home/node/.local/share/fonts
  ln -sfn "$USER_CFG/fonts" "$USER_FONTS_DIR"
  fc-cache -f /home/node/.local/share/fonts >/dev/null 2>&1 || true
  dbg "user fonts overlay linked at $USER_FONTS_DIR"
else
  # No overlay — remove a stale symlink from a previous run.
  [[ -L "$USER_FONTS_DIR" ]] && rm "$USER_FONTS_DIR"
fi

# ── 3. auth.json on a named volume ───────────────────────────────────────────
# Symlink the data-dir path at the secrets volume so opencode keeps finding
# auth.json where it expects it. The legacy migration path (pulling a stray
# auth.json out of the now-gone .agent/opencode/ workspace bind) is no longer
# reachable since the data dir is ephemeral; users with pre-2026-05-20
# state get a one-shot warning at run time if they still have
# .agent/opencode/ in a workspace.
ln -sf "$SECRETS/auth.json" "$OPENCODE_DATA/auth.json"
dbg "auth.json symlink ready"

# ── 4. Workspace .agent/ bootstrap + auto-prune ──────────────────────────────
# .agent/ belongs to the agent end-to-end after the 2026-05-20 state-isolation
# change. Make the conventional subdirs upfront so skills don't have to
# mkdir -p them, then prune ephemeral subdirs (quality-assurance/, scratch/)
# of anything older than 7 days. Hands off task.md and artifacts/ — those
# are user-committable working memory.
if [[ -d /workspace ]]; then
  mkdir -p "$WORKSPACE_AGENT/scratch" "$WORKSPACE_AGENT/artifacts" "$WORKSPACE_AGENT/quality-assurance"
  find "$WORKSPACE_AGENT/quality-assurance" "$WORKSPACE_AGENT/scratch" \
       -mindepth 1 -maxdepth 1 -mtime +7 -exec rm -rf {} + 2>/dev/null || true

  # Orphan-detection: legacy .agent/opencode/ from a pre-2026-05-20 konrad
  # is no longer bound to anything. Tell the user once; don't auto-delete
  # (a pre-migration auth.json could still be in there).
  if [[ -d /workspace/.agent/opencode ]]; then
    warn "found orphan /workspace/.agent/opencode from a pre-2026-05-20 konrad"
    warn "safe to 'rm -rf .agent/opencode/' once you've checked for a stray auth.json"
  fi

  # Orphan-detection: legacy .agent/qa/ from before the 2026-05-22 rename
  # to .agent/quality-assurance/. Same one-shot warning shape.
  if [[ -d /workspace/.agent/qa ]]; then
    warn "found orphan /workspace/.agent/qa from before the quality-assurance rename"
    warn "evidence (if any) lives at /workspace/.agent/quality-assurance/ now"
    warn "safe to 'rm -rf .agent/qa/' once you've moved anything you want to keep"
  fi
fi
dbg ".agent/ bootstrap + prune done"

# ── 5. Session sidecar in the central log dir ────────────────────────────────
# opencode names its own log file by its own timestamp, which we can't
# predict from here. Write a sidecar file with our timestamp recording
# the host workspace path; ls -lt in the central log dir pairs sidecars
# with their opencode logs naturally.
KONRAD_SESSION_TS="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
SESSION_SIDECAR="$OPENCODE_LOG_DIR/${KONRAD_SESSION_TS}-session.txt"
{
  printf 'konrad session\n'
  printf 'workspace: %s\n' "$KONRAD_HOST_WORKSPACE"
  printf 'started:   %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'image:     %s\n' "${HOSTNAME:-(unknown)}"
} > "$SESSION_SIDECAR" 2>/dev/null || true
dbg "session sidecar written to $SESSION_SIDECAR"

dbg "entrypoint done — about to exec: $*"

# opencode writes a fresh, timestamped INFO-level log file on every
# launch with per-line +Xms deltas (the structure that makes "what took
# 2 seconds" easy to spot). The log dir is bind-mounted from the host's
# XDG state dir, so logs accumulate centrally there — not in the workspace.
say "opencode logs (host): $KONRAD_HOST_LOG_DIR"
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
