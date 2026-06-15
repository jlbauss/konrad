#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# konrad egress-proxy entrypoint. Runs in the SIDECAR container — the SAME image
# as the agent, launched by bin/konrad with `konrad-proxy` as its command. The
# sidecar is the only member of the run with a route to the internet; the agent
# container sits on an isolated network and reaches the outside ONLY through here.
#
# Responsibilities:
#   1. Compose the same baked<org<user opencode config the main entrypoint does,
#      so the allow-list tracks the user's REAL provider endpoints.
#   2. Derive the egress allow-list, default-deny:
#        - a baked infra floor (the minimum konrad needs to function),
#        - every provider baseURL host from the merged config,
#        - every BUILT-IN provider the user has connected (`auth.json`) or
#          declared (a `provider` block / a `model` prefix), resolved to a host
#          via the baked provider-id→host map (provider-hosts.json) — these carry
#          no `baseURL` in config; opencode resolves their endpoint from the SDK /
#          models.dev catalog, so without this they'd be silently blocked,
#        - the user's persistent allowed_hosts file (if any),
#        - any hosts bin/konrad passed at runtime (KONRAD_ALLOWED_HOSTS).
#   3. Emit a tinyproxy default-deny config with an anchored host filter, start
#      it, and LIVE-RELOAD the filter (tinyproxy SIGUSR1) whenever `auth.json`
#      changes — so connecting a provider in-session (opencode `/connect`) takes
#      effect within seconds, with no konrad restart and no --no-firewall.
#
# Root-owned + run as the unprivileged node user (like the agent): the allow-list
# logic can't be tampered with from the agent side, and there is no shared writable
# surface between the two containers. auth.json is mounted READ-ONLY; only the
# provider ids (`keys`) are read — never the key material.
set -euo pipefail

PROXY_PORT="${KONRAD_PROXY_PORT:-8888}"
RELOAD_INTERVAL="${KONRAD_PROXY_RELOAD_INTERVAL:-2}"  # seconds between auth.json polls
CONF=/tmp/konrad-tinyproxy.conf
FILTER=/tmp/konrad-allow.filter

KONRAD_BAKED=/etc/konrad
COMPOSE="$KONRAD_BAKED/compose-allowed-hosts.sh"    # the shared, single-source list
AUTH_JSON=/home/node/.opencode-secrets/auth.json   # konrad-secrets volume, RO (ids only)

say() { printf '[konrad proxy] %s\n' "$*" >&2; }

# ── Render the anchored, deduped filter from the shared host list to $1 ───────
# The list itself (floor ∪ provider endpoints ∪ allowed_hosts ∪ runtime hosts ∪
# connected providers from auth.json) is composed by compose-allowed-hosts.sh —
# the SAME script konrad-entrypoint inlines for the model, so the firewall and
# the model's view can never drift. This wrapper only adds the anchoring.
# Anchoring is load-bearing: tinyproxy's filter does substring regex matching, so
# a bare `api.example.com` would ALSO pass `api.example.com.attacker.net`. The
# ^host(:port)?$ anchor closes that bypass. Dots are escaped so they're literal.
# Writes the anchored filter to $1; echoes the plain host list to stdout so the
# caller can log what's allowed. auth.json is RO-mounted; only ids are read.
render_filter() {
  local out="$1" h esc
  : > "$out"
  while IFS= read -r h; do
    [[ -z "$h" ]] && continue
    esc="${h//./\\.}"
    printf '^%s(:[0-9]+)?$\n' "$esc" >> "$out"
    printf '%s\n' "$h"   # plain host → stdout, for the allow-list log line
  done < <("$COMPOSE")
}

# ── tinyproxy config: default-deny destinations, allow-list by host ──────────
# FilterDefaultDeny Yes  → deny every destination except a filter match.
# FilterType ere         → POSIX extended regex (the ^host(:port)?$ anchors).
#                          Replaces the deprecated FilterExtended in tinyproxy 1.11+.
# FilterURLs Off         → match on the destination HOST (covers plain HTTP and
#                          the HTTPS CONNECT target alike), not the full URL.
# No ConnectPort lines   → CONNECT allowed to any port; the host filter is the
#                          real gate (a provider on a non-443 port still works).
# Runs as node (the container already drops to uid 1000 via bin/konrad's userns
# map), so User/Group match the runtime user — no setuid attempt.
cat > "$CONF" <<EOF
User node
Group node
Port ${PROXY_PORT}
Listen 0.0.0.0
Timeout 600
StatHost "konrad.proxy.invalid"
Allow 0.0.0.0/0
Filter "${FILTER}"
FilterDefaultDeny Yes
FilterType ere
FilterCaseSensitive Off
FilterURLs Off
LogLevel Info
EOF

allowed="$(render_filter "$FILTER")"
say "tinyproxy listening on :${PROXY_PORT} — default-deny, allowing: $(echo "$allowed" | tr '\n' ' ')"

# -d: stay in the foreground and log to stderr so podman captures proxy denials.
# Backgrounded so this script can live-reload the filter; the trap stops it on
# teardown (bin/konrad's `podman rm -f` sends SIGTERM).
tinyproxy -d -c "$CONF" &
TP=$!
trap 'kill "$TP" 2>/dev/null || true' EXIT
trap 'exit 0' INT TERM

# ── Live reload: re-derive on auth.json change, SIGUSR1 (no dropped conns) ────
# tinyproxy reloads its config + filter list on SIGUSR1. auth.json is the ONLY
# input that changes mid-run (config/allowed_hosts/runtime hosts are all fixed
# at start), so we gate on its mtime — a cheap stat per tick instead of a full
# config re-merge — and only re-render + signal when the rendered bytes actually
# change. (A start-of-run /connect makes auth.json appear, flipping the mtime.)
auth_mtime() { stat -c %Y "$AUTH_JSON" 2>/dev/null || echo 0; }
prev_mtime="$(auth_mtime)"
while kill -0 "$TP" 2>/dev/null; do
  sleep "$RELOAD_INTERVAL"
  cur_mtime="$(auth_mtime)"
  [[ "$cur_mtime" == "$prev_mtime" ]] && continue
  prev_mtime="$cur_mtime"
  allowed="$(render_filter "$FILTER.new")"
  if cmp -s "$FILTER.new" "$FILTER"; then
    rm -f "$FILTER.new"
  else
    mv "$FILTER.new" "$FILTER"
    kill -USR1 "$TP" 2>/dev/null || true
    say "allow-list updated (connected provider) — allowing: $(echo "$allowed" | tr '\n' ' ')"
  fi
done

wait "$TP"
