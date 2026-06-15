#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Compose konrad's egress allow-list and print it — one plain host per line,
# deduped — to stdout. The SINGLE source of the list, shared by its two
# consumers so they can never drift:
#   - konrad-proxy-entrypoint.sh anchors each line into a tinyproxy filter (the
#     real network boundary),
#   - konrad-entrypoint inlines it into the agent's instructions so the model
#     knows which hosts a fetch can actually reach (a hint, not the gate).
#
# The list = a baked infra floor ∪ every provider baseURL host from the merged
# baked<org<user config ∪ the built-in providers the user has declared (no
# baseURL) or named by `model` prefix, resolved via the baked provider-id→host
# map ∪ the org/user allowed_hosts files ∪ runtime --allow-host
# (KONRAD_ALLOWED_HOSTS) ∪ the providers connected in auth.json (ids only,
# never key material). Default-deny: anything not printed here is refused.
#
# Reads only RO inputs; warnings go to stderr so stdout stays a clean host list.
# Baked root-owned (0755) at /etc/konrad/ so the node runtime user can't tamper
# with the allow-list logic.
set -euo pipefail

KONRAD_BAKED=/etc/konrad
ORG_CFG=/home/node/.config/konrad/org             # bind-mounted RO (optional)
USER_CFG=/home/node/.config/konrad/user            # bind-mounted RO (optional)
PROVIDER_MAP="$KONRAD_BAKED/provider-hosts.json"   # baked provider-id → host map
AUTH_JSON=/home/node/.opencode-secrets/auth.json   # konrad-secrets volume, RO (ids only)

warn() { printf '[konrad allowed-hosts] warning: %s\n' "$*" >&2; }

# ── Baked infra floor — the minimum konrad needs to function ─────────────────
# Kept deliberately minimal (verified empirically — see ARCHITECTURE → Egress
# firewall). Everything else (models.dev, pypi, cloud git hosts, scraping
# targets, …) is opt-in via the org/user allowed_hosts files or --allow-host.
#   host.containers.internal  local model providers (LM Studio / Ollama / llama.cpp)
#   registry.npmjs.org        opencode fetches a non-bundled provider's AI-SDK
#                             adapter at runtime; OpenAI-compatible is bundled.
hosts=(
  host.containers.internal
  registry.npmjs.org
)

# ── Provider-id → host map (baked, generated from models.dev) ─────────────────
declare -A PMAP=()
if [[ -f "$PROVIDER_MAP" ]]; then
  while IFS=$'\t' read -r k v; do
    [[ -n "$k" ]] && PMAP[$k]="$v"
  done < <(jq -r 'to_entries[] | "\(.key)\t\(.value)"' "$PROVIDER_MAP" 2>/dev/null)
else
  warn "$PROVIDER_MAP missing; built-in providers won't be auto-allowed"
fi

# ── Provider endpoints from the merged baked<org<user config ──────────────────
# Same left-fold as konrad-entrypoint, so the list tracks the user's REAL
# providers. We only need hosts, so a merge failure is non-fatal.
merge_inputs=("$KONRAD_BAKED/opencode-defaults.jsonc")
[[ -f "$ORG_CFG/opencode.jsonc" ]]  && merge_inputs+=("$ORG_CFG/opencode.jsonc")
[[ -f "$USER_CFG/opencode.jsonc" ]] && merge_inputs+=("$USER_CFG/opencode.jsonc")

# Extract the host from a scheme://host[:port][/path] baseURL.
host_of() { sed -E 's#^[a-zA-Z][a-zA-Z0-9+.-]*://([^/:]+).*#\1#'; }

if merged="$(node "$KONRAD_BAKED/merge-config.js" "${merge_inputs[@]}" 2>/dev/null)"; then
  # 1. Explicit provider baseURLs (local engines, custom endpoints).
  while IFS= read -r h; do
    [[ -n "$h" ]] && hosts+=("$h")
  done < <(printf '%s' "$merged" \
    | jq -r '.provider // {} | to_entries[] | .value.options.baseURL // empty' | host_of)

  # 2. Built-in providers DECLARED without a baseURL: resolve id → host via map.
  while IFS= read -r id; do
    [[ -n "$id" && -n "${PMAP[$id]:-}" ]] && hosts+=("${PMAP[$id]}")
  done < <(printf '%s' "$merged" \
    | jq -r '.provider // {} | to_entries[] | select(.value.options.baseURL == null) | .key')

  # 3. Providers named only by a `model` prefix (top-level or per-agent).
  while IFS= read -r id; do
    [[ -n "$id" && -n "${PMAP[$id]:-}" ]] && hosts+=("${PMAP[$id]}")
  done < <(printf '%s' "$merged" \
    | jq -r '[.model // empty, (.agent // {} | to_entries[] | .value.model // empty)] | .[] | split("/")[0]')
else
  warn "config merge failed; list = floor + map(auth.json) + runtime hosts"
fi

# ── Persistent allow-list files (org + user; one host per line, # comments) ───
for f in "$ORG_CFG/allowed_hosts" "$USER_CFG/allowed_hosts"; do
  [[ -f "$f" ]] || continue
  while IFS= read -r line; do
    line="${line%%#*}"
    line="${line//[[:space:]]/}"
    [[ -n "$line" ]] && hosts+=("$line")
  done < "$f"
done

# ── Runtime additions (--allow-host / KONRAD_ALLOW_HOST → KONRAD_ALLOWED_HOSTS) ─
if [[ -n "${KONRAD_ALLOWED_HOSTS:-}" ]]; then
  read -r -a _runtime <<<"${KONRAD_ALLOWED_HOSTS//,/ }"   # comma- or space-separated
  hosts+=("${_runtime[@]}")
fi

# ── Connected built-in providers (auth.json — ids only, resolved via map) ─────
if [[ -f "$AUTH_JSON" ]]; then
  while IFS= read -r id; do
    [[ -n "$id" && -n "${PMAP[$id]:-}" ]] && hosts+=("${PMAP[$id]}")
  done < <(jq -r 'keys[]' "$AUTH_JSON" 2>/dev/null || true)
fi

# ── Emit deduped, in first-seen order ────────────────────────────────────────
declare -A seen=()
for h in "${hosts[@]}"; do
  [[ -z "$h" || -n "${seen[$h]:-}" ]] && continue
  seen[$h]=1
  printf '%s\n' "$h"
done
