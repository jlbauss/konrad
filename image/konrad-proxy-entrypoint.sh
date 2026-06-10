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
#        - the user's persistent allowed_hosts file (if any),
#        - any hosts bin/konrad passed at runtime (KONRAD_ALLOWED_HOSTS).
#   3. Emit a tinyproxy default-deny config with an anchored host filter and exec
#      it in the foreground (PID 1 under the container's --init).
#
# Root-owned + run as the unprivileged node user (like the agent): the allow-list
# logic can't be tampered with from the agent side, and there is no shared writable
# surface between the two containers.
set -euo pipefail

PROXY_PORT="${KONRAD_PROXY_PORT:-8888}"
CONF=/tmp/konrad-tinyproxy.conf
FILTER=/tmp/konrad-allow.filter

KONRAD_BAKED=/etc/konrad
ORG_CFG=/home/node/.config/konrad/org      # bind-mounted RO by bin/konrad (optional)
USER_CFG=/home/node/.config/konrad/user     # bind-mounted RO by bin/konrad (optional)

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

# ── Provider endpoints from the merged config ────────────────────────────────
# Same left-fold as image/entrypoint.sh, so the proxy sees exactly the providers
# the agent will use. We only need the hosts, so a merge failure is non-fatal —
# the floor still stands and bin/konrad can pass provider hosts explicitly.
merge_inputs=("$KONRAD_BAKED/opencode-defaults.jsonc")
[[ -f "$ORG_CFG/opencode.jsonc" ]]  && merge_inputs+=("$ORG_CFG/opencode.jsonc")
[[ -f "$USER_CFG/opencode.jsonc" ]] && merge_inputs+=("$USER_CFG/opencode.jsonc")

provider_hosts=()
if merged="$(node "$KONRAD_BAKED/merge-config.js" "${merge_inputs[@]}" 2>/dev/null)"; then
  while IFS= read -r h; do
    [[ -n "$h" ]] && provider_hosts+=("$h")
  done < <(printf '%s' "$merged" \
    | jq -r '.provider // {} | to_entries[] | .value.options.baseURL // empty' \
    | sed -E 's#^[a-zA-Z][a-zA-Z0-9+.-]*://([^/:]+).*#\1#')
else
  say "warning: config merge failed; allow-list = floor + runtime hosts only"
fi

# ── Persistent allow-list files (one host per line, # comments) ──────────────
# Both layers may ship an `allowed_hosts` file alongside the opencode config —
# org for organization-wide additions, user for personal ones. Konrad-specific
# (NOT part of the opencode config merge); read here and unioned in.
file_hosts=()
for f in "$ORG_CFG/allowed_hosts" "$USER_CFG/allowed_hosts"; do
  [[ -f "$f" ]] || continue
  while IFS= read -r line; do
    line="${line%%#*}"
    line="${line//[[:space:]]/}"
    [[ -n "$line" ]] && file_hosts+=("$line")
  done < "$f"
done

# ── Runtime additions from bin/konrad (--allow-host / KONRAD_ALLOW_HOST) ──────
runtime_hosts=()
if [[ -n "${KONRAD_ALLOWED_HOSTS:-}" ]]; then
  # comma- or whitespace-separated
  read -r -a runtime_hosts <<<"${KONRAD_ALLOWED_HOSTS//,/ }"
fi

# ── Union, dedupe, write the anchored filter ─────────────────────────────────
# Anchoring is load-bearing: tinyproxy's filter does substring regex matching, so
# a bare `api.example.com` would ALSO pass `api.example.com.attacker.net`. The
# ^host(:port)?$ anchor closes that bypass. Dots are escaped so they're literal.
all_hosts=("${FLOOR[@]}" "${provider_hosts[@]}" "${file_hosts[@]}" "${runtime_hosts[@]}")
: > "$FILTER"
declare -A seen=()
allow_count=0
for h in "${all_hosts[@]}"; do
  [[ -z "$h" || -n "${seen[$h]:-}" ]] && continue
  seen[$h]=1
  esc="${h//./\\.}"
  printf '^%s(:[0-9]+)?$\n' "$esc" >> "$FILTER"
  say "allow: $h"
  allow_count=$((allow_count + 1))
done

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

say "tinyproxy listening on :${PROXY_PORT} — default-deny, ${allow_count} host(s) allowed"
# -d: stay in the foreground and log to stderr so podman captures proxy denials.
exec tinyproxy -d -c "$CONF"
