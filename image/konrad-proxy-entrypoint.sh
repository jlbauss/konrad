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
ORG_CFG=/home/node/.config/konrad/org      # bind-mounted RO by bin/konrad (optional)
USER_CFG=/home/node/.config/konrad/user     # bind-mounted RO by bin/konrad (optional)
PROVIDER_MAP="$KONRAD_BAKED/provider-hosts.json"   # baked provider-id → host map
AUTH_JSON=/home/node/.opencode-secrets/auth.json   # konrad-secrets volume, RO (ids only)

say() { printf '[konrad proxy] %s\n' "$*" >&2; }

# ── Baked infra floor — the minimum konrad needs to function ─────────────────
# Kept deliberately minimal (verified empirically — see below). Everything else
# (models.dev catalog, pypi for `uv pip install`, cloud git hosts, scraping
# targets, …) is opt-in via the org/user allowed_hosts files or --allow-host.
#   host.containers.internal  local model providers (LM Studio / Ollama / llama.cpp).
#                             Also derived from the baked provider baseURLs, so this
#                             is belt-and-suspenders — local models work regardless.
#   registry.npmjs.org        opencode fetches a provider's AI-SDK adapter at runtime
#                             ONLY when it isn't already bundled. OpenAI-compatible
#                             providers (all three local engines + many remotes) are
#                             bundled and need no fetch; Anthropic/Google/etc. SDKs
#                             are not, so first use of one needs this. (A future
#                             build-time bake of the adapters would drop this too —
#                             see ROADMAP.) models.dev was tested NOT required: a
#                             declared model resolves and runs without it.
FLOOR=(
  host.containers.internal
  registry.npmjs.org
)

# ── Provider-id → host map (baked) ───────────────────────────────────────────
# Generated from models.dev by scripts/resolve-provider-hosts.sh; the source of
# truth for the endpoint of every BUILT-IN provider (openrouter, anthropic, …)
# the user enables with just a key / `/connect` and no explicit baseURL.
declare -A PMAP=()
if [[ -f "$PROVIDER_MAP" ]]; then
  while IFS=$'\t' read -r k v; do
    [[ -n "$k" ]] && PMAP[$k]="$v"
  done < <(jq -r 'to_entries[] | "\(.key)\t\(.value)"' "$PROVIDER_MAP" 2>/dev/null)
else
  say "warning: $PROVIDER_MAP missing; built-in providers won't be auto-allowed"
fi

# ── Provider endpoints from the merged config (computed ONCE — RO inputs) ─────
# Same left-fold as image/entrypoint.sh, so the proxy sees exactly the providers
# the agent will use. We only need hosts, so a merge failure is non-fatal — the
# floor, the map, and auth.json still stand.
merge_inputs=("$KONRAD_BAKED/opencode-defaults.jsonc")
[[ -f "$ORG_CFG/opencode.jsonc" ]]  && merge_inputs+=("$ORG_CFG/opencode.jsonc")
[[ -f "$USER_CFG/opencode.jsonc" ]] && merge_inputs+=("$USER_CFG/opencode.jsonc")

# Extract the host from a scheme://host[:port][/path] baseURL (scheme stripped,
# port/path dropped) — the same reduction scripts/resolve-provider-hosts.sh does.
host_of() { sed -E 's#^[a-zA-Z][a-zA-Z0-9+.-]*://([^/:]+).*#\1#'; }

static_hosts=("${FLOOR[@]}")
if merged="$(node "$KONRAD_BAKED/merge-config.js" "${merge_inputs[@]}" 2>/dev/null)"; then
  # 1. Explicit provider baseURLs win (local engines, custom endpoints).
  while IFS= read -r h; do
    [[ -n "$h" ]] && static_hosts+=("$h")
  done < <(printf '%s' "$merged" \
    | jq -r '.provider // {} | to_entries[] | .value.options.baseURL // empty' | host_of)

  # 2. Built-in providers DECLARED in config but WITHOUT a baseURL (e.g. the
  #    README recipes that set only options.apiKey): resolve id → host via the map.
  while IFS= read -r id; do
    [[ -n "$id" && -n "${PMAP[$id]:-}" ]] && static_hosts+=("${PMAP[$id]}")
  done < <(printf '%s' "$merged" \
    | jq -r '.provider // {} | to_entries[] | select(.value.options.baseURL == null) | .key')

  # 3. Providers named only by a `model` prefix (top-level or per-agent), e.g.
  #    "model": "openrouter/…" with the key supplied via env and no provider block.
  while IFS= read -r id; do
    [[ -n "$id" && -n "${PMAP[$id]:-}" ]] && static_hosts+=("${PMAP[$id]}")
  done < <(printf '%s' "$merged" \
    | jq -r '[.model // empty, (.agent // {} | to_entries[] | .value.model // empty)] | .[] | split("/")[0]')
else
  say "warning: config merge failed; allow-list = floor + map(auth.json) + runtime hosts"
fi

# ── Persistent allow-list files (one host per line, # comments) ──────────────
# Both layers may ship an `allowed_hosts` file alongside the opencode config —
# org for organization-wide additions, user for personal ones. Konrad-specific
# (NOT part of the opencode config merge); read here and unioned in.
for f in "$ORG_CFG/allowed_hosts" "$USER_CFG/allowed_hosts"; do
  [[ -f "$f" ]] || continue
  while IFS= read -r line; do
    line="${line%%#*}"
    line="${line//[[:space:]]/}"
    [[ -n "$line" ]] && static_hosts+=("$line")
  done < "$f"
done

# ── Runtime additions from bin/konrad (--allow-host / KONRAD_ALLOW_HOST) ──────
if [[ -n "${KONRAD_ALLOWED_HOSTS:-}" ]]; then
  # comma- or whitespace-separated
  read -r -a _runtime <<<"${KONRAD_ALLOWED_HOSTS//,/ }"
  static_hosts+=("${_runtime[@]}")
fi

# ── auth.json provider ids (DYNAMIC — re-read every reload tick) ──────────────
# A provider is unusable without credentials, so `auth.json` (written by opencode
# `/connect`) is the canonical signal for "providers the user actually uses",
# covering the interactive path. We read only the ids, never the key values.
auth_ids() {
  [[ -f "$AUTH_JSON" ]] || return 0
  jq -r 'keys[]' "$AUTH_JSON" 2>/dev/null || true
}

# ── Render the anchored, deduped filter (static ∪ map[auth ids]) to $1 ────────
# Anchoring is load-bearing: tinyproxy's filter does substring regex matching, so
# a bare `api.example.com` would ALSO pass `api.example.com.attacker.net`. The
# ^host(:port)?$ anchor closes that bypass. Dots are escaped so they're literal.
# Writes the anchored filter to $1 and echoes the plain (deduped) host list to
# stdout so the caller can log what's allowed.
render_filter() {
  local out="$1" h esc id
  local all=("${static_hosts[@]}")
  while IFS= read -r id; do
    [[ -n "$id" && -n "${PMAP[$id]:-}" ]] && all+=("${PMAP[$id]}")
  done < <(auth_ids)

  declare -A seen=()
  : > "$out"
  for h in "${all[@]}"; do
    [[ -z "$h" || -n "${seen[$h]:-}" ]] && continue
    seen[$h]=1
    esc="${h//./\\.}"
    printf '^%s(:[0-9]+)?$\n' "$esc" >> "$out"
    printf '%s\n' "$h"   # plain host → stdout, for the allow-list log line
  done
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
# tinyproxy reloads its config + filter list on SIGUSR1. Only auth.json changes
# mid-run (config/allowed_hosts are RO mounts), so a poll of the rendered filter
# is enough; we signal only when the bytes actually change.
while kill -0 "$TP" 2>/dev/null; do
  sleep "$RELOAD_INTERVAL"
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
