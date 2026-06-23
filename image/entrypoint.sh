#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
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

ORG_CFG=/home/node/.config/konrad/org          # org layer  (bind-mounted from host, optional)
USER_CFG=/home/node/.config/konrad/user        # user layer (bind-mounted from host, optional)
KONRAD_BAKED=/etc/konrad                        # everything below was shipped in the image

KONRAD_DEBUG="${KONRAD_DEBUG:-0}"
KONRAD_HOST_WORKSPACE="${KONRAD_HOST_WORKSPACE:-(unknown — KONRAD_HOST_WORKSPACE not set)}"
KONRAD_HOST_LOG_DIR="${KONRAD_HOST_LOG_DIR:-(unknown — KONRAD_HOST_LOG_DIR not set)}"

# Output style — mirrors bin/konrad's helpers so a launch reads as one continuous
# sequence: the host prints the bold "konrad" header, the container continues the
# indented ✓/→ steps under it. Color is gated on an interactive stderr (a TTY)
# with NO_COLOR unset, so `konrad run` / piped / proxy-log output stays plain.
if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
  _C_OK=$'\033[32m'; _C_GO=$'\033[36m'; _C_WARN=$'\033[33m'
  _C_ERR=$'\033[31m'; _C_DIM=$'\033[2m'; _C_OFF=$'\033[0m'
else
  _C_OK=''; _C_GO=''; _C_WARN=''; _C_ERR=''; _C_DIM=''; _C_OFF=''
fi
step()  { printf '  %s✓%s  %s\n'        "$_C_OK"  "$_C_OFF" "$*" >&2; }
go()    { printf '  %s→%s  %s\n'        "$_C_GO"  "$_C_OFF" "$*" >&2; }
say()   { printf '%skonrad%s %s\n'      "$_C_DIM" "$_C_OFF" "$*" >&2; }
warn()  { printf '%skonrad%s %swarning:%s %s\n' "$_C_DIM" "$_C_OFF" "$_C_WARN" "$_C_OFF" "$*" >&2; }
fatal() { printf '%skonrad%s %serror:%s %s\n'   "$_C_DIM" "$_C_OFF" "$_C_ERR" "$_C_OFF" "$*" >&2; exit 1; }
dbg() {
  [[ "$KONRAD_DEBUG" != "1" ]] && return 0
  printf '[konrad container debug %s] %s\n' "$(date +%H:%M:%S.%3N)" "$*" >&2
}

# Shared root→node privilege-drop helper (exec_as_node), used by the root prelude
# below. One canonical implementation; sourced, not executed.
# shellcheck source=konrad-privdrop.sh
. /usr/local/lib/konrad-privdrop.sh \
  || fatal "missing /usr/local/lib/konrad-privdrop.sh (broken image)"

valid_ipv4() { [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; }

# ── 0. Root prelude (apple/container only) — privileged setup, then drop ──────
# This entrypoint is the image ENTRYPOINT for BOTH the agent and the egress proxy
# (the proxy is this image launched with `konrad-proxy` as its command). On
# Apple's `container` engine bin/konrad starts one or the other as uid 0 to do a
# single privileged network step, identified by which env var it sets, then we
# drop to the unprivileged node user — so all real work (this script's remainder
# and the exec'd command alike) runs as node, never root. Podman and the
# firewall-off path never start us as root, so this block is wholly inert there.
#
#   KONRAD_SEAL_GATEWAY  (agent) — apple/container's --internal net is "host-only":
#       its gateway IS the Mac host, so a service on 0.0.0.0 there would be
#       reachable DIRECTLY from the agent, bypassing the egress proxy (rootless
#       Podman has no such route — "network unreachable" to the host; see
#       ARCHITECTURE → Egress firewall). bin/konrad adds CAP_NET_ADMIN and hands
#       us the gateway IP; we blackhole the route to it. The route persists as
#       kernel state the dropped node user can't remove, so the agent ends up
#       both sealed and capability-less. After this, the ONLY path to the host is
#       the same as on Podman: via the proxy, at host.containers.internal.
#   KONRAD_HOST_ALIAS_IP (proxy) — apple/container injects no host.containers.internal
#       alias and has no --add-host, so we map that name (konrad's canonical
#       local-model host, in the allow-list floor) to the egress net's gateway —
#       the Mac host — in /etc/hosts, so tinyproxy can resolve and forward a
#       model request. Podman gets this alias from the engine for free.
#
# Fail CLOSED: a malformed value or a failed privileged step aborts the container
# rather than running with the leak open / silently broken. We always drop to
# node at the end, so even an unexpected uid-0 start never runs the workload as
# root. The uid guard makes the re-exec skip this block (node ≠ 0).
if [[ "$(id -u)" == "0" ]]; then
  if [[ -n "${KONRAD_SEAL_GATEWAY:-}" ]]; then
    valid_ipv4 "$KONRAD_SEAL_GATEWAY" \
      || fatal "refusing to seal — KONRAD_SEAL_GATEWAY is not a valid IPv4 address: '$KONRAD_SEAL_GATEWAY'"
    dbg "egress seal: blackholing host-gateway route $KONRAD_SEAL_GATEWAY (host reachable only via the proxy)"
    ip route add blackhole "$KONRAD_SEAL_GATEWAY/32" \
      || fatal "could not install the egress seal route (is CAP_NET_ADMIN present?) — aborting rather than run with the host-gateway leak open"
    # A phase step, not a general say() line, so it reads as part of the launch
    # sequence (✓ firewall → ✓ egress seal → ✓ config) instead of interrupting
    # it; the gateway IP is -v-only detail (above). Shown only on apple/container
    # (Podman sets no KONRAD_SEAL_GATEWAY — its --internal net has no host route).
    step "egress seal"
  fi
  if [[ -n "${KONRAD_HOST_ALIAS_IP:-}" ]]; then
    valid_ipv4 "$KONRAD_HOST_ALIAS_IP" \
      || fatal "KONRAD_HOST_ALIAS_IP is not a valid IPv4 address: '$KONRAD_HOST_ALIAS_IP'"
    printf '%s host.containers.internal\n' "$KONRAD_HOST_ALIAS_IP" >> /etc/hosts \
      || fatal "could not write the local-model host alias to /etc/hosts"
    # Pure plumbing in the (detached) proxy — its output never reaches the user's
    # terminal anyway, so keep it to -v rather than a phase step.
    dbg "local-model host alias: host.containers.internal -> $KONRAD_HOST_ALIAS_IP"
  fi
  # Clear so they never reach the workload's environment; the uid guard already
  # blocks re-entry, this just keeps the dropped process's env clean.
  unset KONRAD_SEAL_GATEWAY KONRAD_HOST_ALIAS_IP
  dbg "root prelude done; dropping to node"
  exec_as_node "$0" "$@"
fi

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

# Name exactly which layers compose, so "baked + user" / "baked + org + user" /
# "baked" reads at a glance — no ambiguous overlay count.
config_layers="baked"
[[ -f "$ORG_CFG/opencode.jsonc" ]]  && config_layers="$config_layers + org"
[[ -f "$USER_CFG/opencode.jsonc" ]] && config_layers="$config_layers + user"
step "config · $config_layers"
node "$KONRAD_BAKED/merge-config.js" "${merge_inputs[@]}" > "$TARGET_JSONC"
dbg "config composed at $TARGET_JSONC"

# Layered model instructions need NO post-merge surgery here: the baked
# opencode.jsonc declares one glob per layer's instructions/ dir (baked < org <
# user) plus a back-compat literal for the org AGENTS.md, and opencode expands
# them itself — skipping absent dirs/files, de-duplicating, preserving order
# (see its Instruction.systemPaths: ~/ and absolute paths supported, missing
# entries contribute nothing). So org/user add instructions by dropping a *.md
# into their instructions/ dir — no jq, no array-replace footgun, no knowledge
# of guest paths. The org AGENTS.md jq special-case this file used to carry is
# retired into that baked glob list. See ARCHITECTURE → Configuration &
# instructions.

# ── 1b. Inline the egress allow-list into the agent's instructions ───────────
# The model can't see the firewall's allow-list (the proxy is a separate
# container with no shared writable surface — deliberate). So derive the SAME
# list here, with the SAME compose-allowed-hosts.sh the proxy filters on, and
# hand it to the model as a concrete list of reachable hosts — saving it from
# spending turns on fetches the firewall will 403. We just WRITE the file into
# the baked instructions/ dir; the baked `instructions` glob over that dir picks
# it up like any other instruction file (no jq append needed). Only when the
# firewall is actually on (HTTP_PROXY set by bin/konrad) — under --no-firewall
# everything is reachable, so a list would mislead, and we leave the file
# unwritten so the glob simply skips it. Snapshot at session start: a mid-session
# `/connect` updates the firewall (it live-reloads) but NOT this list — the
# firewall stays the source of truth; this is only a hint. The compose script is
# baked and on PATH (smoke-tested). The config dir is ephemeral (fresh per
# --rm container), so there's no stale file to clear on a firewall-off run.
if [[ -n "${HTTP_PROXY:-}" ]]; then
  ALLOWED_HOSTS_MD="$OPENCODE_CFG/instructions/konrad-allowed-hosts.md"
  # shellcheck disable=SC2016  # backticks below are literal markdown, not subshells
  {
    printf '# Reachable hosts (egress allow-list)\n\n'
    printf 'Network egress is default-deny behind a filtering proxy. A `curl` / fetch\n'
    printf '/ `git` / `pip install` to any host NOT in the list below is refused\n'
    printf "(connection error or 403) — it's policy, not an outage, so don't retry in\n"
    printf 'a loop. The user can open one for a run with `konrad --allow-host <host>`\n'
    printf 'or permanently via an `allowed_hosts` file in their config layer.\n\n'
    printf 'Reachable right now (snapshot at session start):\n\n'
    "$KONRAD_BAKED/compose-allowed-hosts.sh" 2>/dev/null | sed 's/^/- /'
  } > "$ALLOWED_HOSTS_MD"
  dbg "egress allow-list written for the instructions glob ($ALLOWED_HOSTS_MD)"
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

# Remote-MCP OAuth tokens land in a sibling file (opencode writes mcp-auth.json
# in the data dir, separate from auth.json). Same treatment, same reason: pin it
# to the secrets volume so a browser MCP login (e.g. `konrad mcp-auth`) survives
# the ephemeral container instead of evaporating on the next run.
ln -sf "$SECRETS/mcp-auth.json" "$OPENCODE_DATA/mcp-auth.json"
dbg "mcp-auth.json symlink ready"

# konrad no longer touches the workspace at startup: it neither creates the
# .agent/ tree (the agent and the quality-assurance helper mkdir -p their own
# dirs on demand) nor edits .gitignore nor writes a session sidecar (opencode's
# own per-launch log is enough). The workspace bind is the agent's to shape.

dbg "entrypoint done — about to exec: $*"

# Final handoff line — match the message to what we actually exec. `$1`/`$2` are
# the command: `opencode` (TUI) / `opencode run` / `opencode auth login` /
# `opencode mcp auth`, `bash` for `shell`, or `konrad-proxy` for the (detached,
# log-only) firewall sidecar. The host's bind-mounted log dir already collects
# opencode's per-launch log; the path pointer is -v-only noise otherwise.
dbg "opencode logs (host): $KONRAD_HOST_LOG_DIR"
case "$1" in
  opencode)
    case "${2:-}" in
      auth) go "connecting a provider" ;;
      mcp)  go "authenticating MCP server" ;;
      run)  go "opencode (run)" ;;
      *)    go "opencode" ;;
    esac
    ;;
  bash) go "shell" ;;
esac

# Raw HTTP trace — DELIBERATELY NOT tied to -v/KONRAD_DEBUG. Asking Bun to
# print every fetch/http call to fd 2 (full request + response headers) buries
# everything else: a normal cold-cache plugin resolution looks like a hang
# (hit 2026-06-08). The structured file log opencode writes per launch — with
# +Xms line deltas — is the better "what's slow" tool, so plain -v just points
# at it (see the host log line above). The firehose stays available for the
# rare network-stall hunt the file log can't surface (models.dev catalog,
# plugin install probes), behind its own explicit opt-in: KONRAD_TRACE_FETCH=1.
if [[ "${KONRAD_TRACE_FETCH:-0}" == "1" ]]; then
  export BUN_CONFIG_VERBOSE_FETCH=true
  dbg "BUN_CONFIG_VERBOSE_FETCH=true (KONRAD_TRACE_FETCH)"
fi

exec "$@"
