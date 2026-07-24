#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Inline model discovery — probe each configured OpenAI-compatible provider's
# /models endpoint and print a discovery fragment to stdout that konrad-entrypoint
# merges BELOW the composed config, so discovery fills the model picker while any
# explicitly-declared model still wins. Replaces the dropped
# opencode-models-discovery plugin (re-adding it cost ~16 s/run through config, or
# re-introduced a fragile build-time dependency plus a 3 s-per-provider SEQUENTIAL
# probe); this is a bounded, PARALLEL probe with no extra dependency. See
# ARCHITECTURE → Configuration & instructions.
#
# Usage: discover-models.sh <composed-config.json>
#   <composed-config.json> is konrad-entrypoint's already-merged (baked<org<user)
#   opencode config — plain JSON (merge-config.js output), so we jq it directly
#   rather than re-running the merge (unlike compose-allowed-hosts.sh, which has
#   no pre-merged file to hand).
#
# Fragment shape (an empty object when nothing is discovered — a no-op merge):
#   { "provider": { "<id>": { "models": { "<model-id>": { "limit": { "context": N, "output": M } } } } } }
# opencode's schema requires BOTH limit keys once a `limit` object is present, so a
# discovered context always ships with an `output` too (defaulted — see below).
# limit.context is set whenever the server can tell us a window, from whichever
# endpoint carries it — opencode's auto-compaction keys off limit.context (with it
# 0/unset, compaction never fires and the model is treated as unbounded), so every
# provider reaches the same service level:
#   - vLLM        — max_model_len, already on /v1/models
#   - llama.cpp   — meta.n_ctx, already on /v1/models
#   - LM Studio   — max_context_length, from its native /api/v0/models
#   - Ollama      — model_info."<arch>.context_length", from /api/show per model
# The /v1/models call is universal (it's the model LIST for every server); the
# native endpoints are queried ONLY to fill a context the list didn't carry, so
# vLLM/llama.cpp pay nothing extra. We never GUESS a window (a wrong value
# mis-compacts): a server that exposes it nowhere leaves the model bare, and you
# declare limit.context yourself (README → Configuration). limit.output is NOT
# advertised by any of these endpoints, so it's derived as context/6 (floor 2048,
# capped at the window). That's not just schema-appeasement: opencode subtracts
# limit.output from the context to size its auto-compaction budget
# (usable = context - min(output, 32000)) AND sends it verbatim as max_tokens, so
# a proportional ~17% reserve leaves ~83% usable — vs opencode's own unset-output
# fallback of 32000, which on a 32k model would leave a ~768-token sliver. Declare
# a model to override it.
#
# Key invariant: this runs as the unprivileged node user INSIDE the sandbox and
# BEFORE opencode is exec'd (no agent in the loop yet). It reads each provider key
# from the mounted, read-only auth.json and sends it only to the very endpoint
# opencode itself would call — through the firewall proxy when the firewall is on
# (curl honours HTTP(S)_PROXY, as Bun/opencode does) — so the HOST and the
# PROXY-AS-DECIDER never see the key, and authenticated REMOTE endpoints are
# discovered too, not just keyless local ones.
#
# Never fails the launch: every probe is best-effort and bounded, and the worst
# case is an unchanged config. Opt out entirely with KONRAD_NO_DISCOVERY=1; tune
# the per-probe ceiling with KONRAD_DISCOVERY_TIMEOUT (seconds, default 2). Because
# the probes run in parallel that ceiling also caps the total latency added — and
# it is what bounds the macOS podman-machine "dropped connect" hang that made the
# old plugin's sequential probe so slow on konrad's three pre-wired local ports.
set -euo pipefail

CONFIG="${1:?usage: discover-models.sh <composed-config.json>}"
AUTH_JSON=/home/node/.opencode-secrets/auth.json
TIMEOUT="${KONRAD_DISCOVERY_TIMEOUT:-2}"

warn() { printf '[konrad model-discovery] warning: %s\n' "$*" >&2; }

command -v curl >/dev/null 2>&1 || { warn "curl missing; skipping discovery"; printf '{}\n'; exit 0; }

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# Thin curl wrapper: fail on HTTP error, silent, bounded connect + total time,
# proxy-honoring (inherits HTTP(S)_PROXY like opencode does). Best-effort — prints
# nothing and returns 0 on any failure, so no single call can abort the script.
# The bearer token rides curl's argv, which is safe here precisely because nothing
# else is running yet to read it: the probe completes before opencode (and any
# agent) is exec'd.
_curl() { curl -fsS --connect-timeout "$TIMEOUT" --max-time "$TIMEOUT" "$@" 2>/dev/null || true; }

# Probe one provider and write "<provider>\t<model>\t<context>" lines (context
# empty when no endpoint exposes one). /v1/models is the universal model LIST;
# context comes from it directly (vLLM, llama.cpp) or, for the models it leaves
# without one, from the server's native endpoint (LM Studio, Ollama) — see the
# per-server map in the header. Embedding models are dropped by name (cosmetic now
# that upstream stopped rejecting the modality, but still tidy).
probe() {
  local id="$1" baseurl="$2" key="$3" out="$4"
  local root="${baseurl%/}"; root="${root%/v1}"     # server root, trailing /v1 stripped
  local auth=()
  [[ -n "$key" ]] && auth=(-H "Authorization: Bearer $key")

  # Universal model LIST (the OpenAI-compatible catalog every server serves).
  local list_json
  list_json="$(_curl ${auth[@]+"${auth[@]}"} "${baseurl%/}/models")"
  [[ -n "$list_json" ]] || return 0

  # Context the OpenAI response ALREADY carries (vLLM / llama.cpp). Non-null
  # entries only, so enrichment can fill gaps without a null clobbering a value.
  local base_map
  base_map="$(printf '%s' "$list_json" | jq -c '
      [ .data[]? | select(.id)
        | { key: .id,
            value: ( .max_model_len // .meta.n_ctx // .context_length
                     // .max_context_length // .context_window // null ) }
        | select(.value != null) ] | from_entries' 2>/dev/null || printf '{}')"

  # Context ENRICHMENT — only when some model still lacks a window (so vLLM /
  # llama.cpp make no extra call), and only from the server's own native API.
  local enrich_map='{}' missing
  missing="$(printf '%s' "$list_json" | jq -r --argjson b "$base_map" \
      '[ .data[]? | select(.id) | select($b[.id] == null) ] | length' 2>/dev/null || printf 0)"
  if [[ "${missing:-0}" -gt 0 ]]; then
    # LM Studio: native /api/v0/models carries max_context_length per model.
    local lms_json
    lms_json="$(_curl ${auth[@]+"${auth[@]}"} "$root/api/v0/models")"
    if printf '%s' "$lms_json" | jq -e '.data' >/dev/null 2>&1; then
      enrich_map="$(printf '%s' "$lms_json" | jq -c '
          [ .data[]? | select(.id) | select(.max_context_length)
            | { key: .id, value: .max_context_length } ] | from_entries' 2>/dev/null || printf '{}')"
    else
      # Ollama: /v1/models has no context, so read each model's native /api/show
      # → model_info."<arch>.context_length". /api/tags gates it, so a non-Ollama
      # server pays a single 404 here, not one POST per model.
      local tags_json
      tags_json="$(_curl ${auth[@]+"${auth[@]}"} "$root/api/tags")"
      if printf '%s' "$tags_json" | jq -e '.models' >/dev/null 2>&1; then
        local pairs body
        pairs="$(while IFS= read -r m; do
                   [[ -n "$m" ]] || continue
                   body="$(jq -cn --arg m "$m" '{model: $m}')"
                   _curl ${auth[@]+"${auth[@]}"} -H 'Content-Type: application/json' \
                        "$root/api/show" -d "$body" \
                     | jq -r --arg m "$m" '(.model_info // {} | to_entries[]
                         | select(.key | endswith(".context_length")) | .value) as $c
                         | select($c != null) | [$m, $c] | @tsv' 2>/dev/null || true
                 done < <(printf '%s' "$tags_json" | jq -r '.models[]?.name // empty' 2>/dev/null))"
        enrich_map="$(printf '%s' "$pairs" | jq -R -s -c '
            split("\n") | map(select(length > 0) | split("\t"))
            | reduce .[] as $r ({}; .[$r[0]] = ($r[1] | tonumber))' 2>/dev/null || printf '{}')"
      fi
    fi
  fi

  # Emit: context wins from the OpenAI response, else enrichment, else empty.
  local ctxmap
  ctxmap="$(printf '%s' "$enrich_map" | jq -c --argjson b "$base_map" '. + $b' 2>/dev/null || printf '{}')"
  printf '%s' "$list_json" | jq -r --arg pid "$id" --argjson ctx "$ctxmap" '
      .data[]? | select(.id)
      | select((.id | ascii_downcase | contains("embed")) | not)
      | [ $pid, .id, ($ctx[.id] // "") ] | @tsv' 2>/dev/null > "$out" || true
}

# Enumerate providers with an explicit options.baseURL (local engines + custom or
# self-hosted OpenAI-compatible endpoints). Built-in providers with no baseURL
# (openai, anthropic, …) ship their own model catalogs and are skipped — the same
# scoping the egress allow-list derivation uses. Fire every probe in parallel,
# each writing its own file (no shared-write race), then wait for the bounded set.
i=0
while IFS=$'\t' read -r id baseurl; do
  [[ -n "$id" && -n "$baseurl" ]] || continue
  key=""
  [[ -f "$AUTH_JSON" ]] \
    && key="$(jq -r --arg id "$id" '.[$id].key // empty' "$AUTH_JSON" 2>/dev/null || true)"
  probe "$id" "$baseurl" "$key" "$tmpdir/probe.$i" &
  i=$((i + 1))
done < <(jq -r '.provider // {} | to_entries[]
                | select(.value.options.baseURL) | "\(.key)\t\(.value.options.baseURL)"' \
              "$CONFIG" 2>/dev/null || true)

wait

# Assemble the nested fragment from every "<provider>\t<model>\t<context>" line.
# Each model becomes {} — or { limit: { context: N } } when the probe captured a
# numeric window. Empty input (no baseURL providers, or every probe came back
# empty) collapses to {}. The `|| true` guards the common no-match glob: with no
# probe.* files `cat` exits non-zero, which under `pipefail` would make this
# best-effort script exit 1.
{ cat "$tmpdir"/probe.* 2>/dev/null || true; } | jq -R -s '
  split("\n")
  | map(select(length > 0) | split("\t"))
  | reduce .[] as $row ({};
      .provider[$row[0]].models[$row[1]] +=
        (if ($row[2] // "") | test("^[0-9]+$")
         then ( ($row[2] | tonumber) as $c
                # opencode requires BOTH keys once a `limit` object is present, and
                # no endpoint advertises an output cap. opencode both subtracts
                # limit.output from context to size auto-compaction AND sends it as
                # max_tokens, so derive a proportional context/6 (floor 2048), capped
                # at the window so it never exceeds a tiny context. Declared wins.
                | ([ ($c / 6 | floor), 2048 ] | max) as $o
                | { limit: { context: $c, output: ([ $o, $c ] | min) } } )
         else {} end))
'
