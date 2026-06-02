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

ORG_CFG=/home/node/.config/konrad/org          # org layer  (bind-mounted from host, optional)
USER_CFG=/home/node/.config/konrad/user        # user layer (bind-mounted from host, optional)
KONRAD_BAKED=/etc/konrad                        # everything below was shipped in the image

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

# ── 1. Compose opencode.jsonc (baked defaults + optional org + user layers) ──
# Up to three layers, left-folded so each later layer wins on conflicts:
#   1. /etc/konrad/opencode-defaults.jsonc          (baked into image)
#   2. ~/.config/konrad/org/opencode.jsonc          (org layer, optional)
#   3. ~/.config/konrad/user/opencode.jsonc         (user layer, optional)
# merge-config.js always runs (even with no overlays) so the output is the
# same comment-stripped JSON opencode reads on the merge path — no special
# raw-cp branch to keep in sync.
TARGET_JSONC="$OPENCODE_CFG/opencode.jsonc"

merge_inputs=("$KONRAD_BAKED/opencode-defaults.jsonc")
[[ -f "$ORG_CFG/opencode.jsonc" ]]  && merge_inputs+=("$ORG_CFG/opencode.jsonc")
[[ -f "$USER_CFG/opencode.jsonc" ]] && merge_inputs+=("$USER_CFG/opencode.jsonc")

if (( ${#merge_inputs[@]} > 1 )); then
  say "composing config: baked + $(( ${#merge_inputs[@]} - 1 )) overlay(s) (org/user)"
else
  say "composing config: baked defaults (no overrides)"
fi
node "$KONRAD_BAKED/merge-config.js" "${merge_inputs[@]}" > "$TARGET_JSONC"
dbg "config composed at $TARGET_JSONC"

# Org instructions ride the system `instructions` channel — the same channel
# as the baked environment.md — appended AFTER the merge so the array-replace
# rule can never silently drop them (a user override of `instructions` would
# otherwise discard org content). The org file is referenced at its read-only
# mount path. Precedence in opencode's instruction load order ends up:
# environment.md → org → (user/project AGENTS.md, which opencode discovers on
# its own). This is what makes org content "system-channel" rather than the
# user-owned global AGENTS.md. jq is on PATH in the image (smoke-tested).
if [[ -f "$ORG_CFG/AGENTS.md" ]]; then
  tmp_jsonc="$(mktemp)"
  jq --arg p "$ORG_CFG/AGENTS.md" '.instructions += [$p]' "$TARGET_JSONC" > "$tmp_jsonc" \
    && mv "$tmp_jsonc" "$TARGET_JSONC"
  dbg "org AGENTS.md appended to .instructions"
fi

# ── 2. Layer in org- and user-shipped agents / skills / AGENTS.md ────────────
# Each piece is optional. `cp -r` means a later layer OVERWRITES the baked (or
# org) files on name collision (e.g. a user-shipped `agents/konrad.md` replaces
# ours). That's intentional: the "I want to run my own konrad agent" escape
# hatch. Layer order matches the config merge — baked (already in $OPENCODE_CFG)
# < org < user — so we cp org's tree first, then user's on top.
for layer in "$ORG_CFG" "$USER_CFG"; do
  [[ -d "$layer/agents" ]] && cp -r "$layer/agents/." "$OPENCODE_CFG/agents/"
  [[ -d "$layer/skills" ]] && cp -r "$layer/skills/." "$OPENCODE_CFG/skills/"
done

# The user's global AGENTS.md lands where opencode auto-discovers it
# (~/.config/opencode/AGENTS.md). The ORG AGENTS.md deliberately does NOT go
# here — it rides the `instructions` channel (§1 above) so the discovered
# global AGENTS.md stays the user's alone. See docs/design/org-config-layer.md.
if [[ -f "$USER_CFG/AGENTS.md" ]]; then
  cp "$USER_CFG/AGENTS.md" "$OPENCODE_CFG/AGENTS.md"
fi
dbg "org + user content layered in"

# ── 2b. Font overlays (org + user) ───────────────────────────────────────────
# Anything dropped into the org/ or user/ fonts dir on the host shows up under
# the matching mount here (bind-mounted by bin/konrad). Symlink each into
# ~/.local/share/fonts/, which fontconfig watches by default, and refresh the
# cache once at the end. Symlinks rather than copies so adding a font on the
# host is picked up on the next launch without an extra step. Each layer gets
# its own link name (konrad-org / konrad-user); fontconfig sees both.
FONTS_BASE=/home/node/.local/share/fonts
mkdir -p "$FONTS_BASE"
FONTS_CHANGED=0
for pair in "org:$ORG_CFG/fonts" "user:$USER_CFG/fonts"; do
  label="${pair%%:*}"
  src="${pair#*:}"
  link="$FONTS_BASE/konrad-$label"
  count=0
  [[ -d "$src" ]] && count=$(find "$src" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null | wc -l)
  if (( count > 0 )); then
    ln -sfn "$src" "$link"
    FONTS_CHANGED=1
    dbg "fonts overlay linked: $link → $src"
  else
    # No overlay for this layer — remove a stale symlink from a previous run.
    [[ -L "$link" ]] && rm "$link"
  fi
done
if (( FONTS_CHANGED )); then
  fc-cache -f "$FONTS_BASE" >/dev/null 2>&1 || true
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
