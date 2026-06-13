#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Regenerate image/konrad-defaults/provider-hosts.json — the provider-id → host
# map the egress proxy uses to allow-list opencode's BUILT-IN providers (the ones
# the user enables with just an API key / `/connect`, carrying no explicit
# `baseURL` in config). See image/konrad-proxy-entrypoint.sh.
#
# Why a committed, generated artifact (not a build-time fetch): the image is the
# canonical artifact and its layers are kept byte-stable so users skip
# re-downloads. A live models.dev fetch inside `docker build` would drift the
# layer daily; committing the reduced map (and reviewing its diff) is the same
# "pin upstream data, bake the pinned copy" pattern as image/locks/. Run by the
# daily lock-refresh bot (.gitlab-ci.yml) and by hand when needed.
#
# Sources, unioned (supplement wins on conflict):
#   1. models.dev/api.json — every provider whose catalog `api` baseURL is a
#      plain scheme://host (covers openrouter + the whole openai-compatible long
#      tail). Hosts with `${VAR}` / `{…}` templates (account/region endpoints
#      like azure, bedrock, vertex, snowflake) are skipped — those stay
#      user-supplied via allowed_hosts / --allow-host.
#   2. scripts/provider-hosts.supplement.json — the first-party `@ai-sdk/*`
#      providers (anthropic, openai, google, …) the catalog leaves with a null
#      `api` because their host lives in the SDK package, not the catalog.
set -euo pipefail

CATALOG_URL="${KONRAD_MODELS_CATALOG_URL:-https://models.dev/api.json}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUPPLEMENT="$REPO_ROOT/scripts/provider-hosts.supplement.json"
OUT="$REPO_ROOT/image/konrad-defaults/provider-hosts.json"

command -v jq   >/dev/null || { echo "resolve-provider-hosts: jq is required" >&2; exit 1; }
command -v curl >/dev/null || { echo "resolve-provider-hosts: curl is required" >&2; exit 1; }

catalog="$(curl -fsS --max-time 60 "$CATALOG_URL")" \
  || { echo "resolve-provider-hosts: could not fetch $CATALOG_URL" >&2; exit 1; }

# Reduce the catalog to id→host (scheme stripped, port/path dropped — the same
# host extraction the proxy uses), drop template hosts, then union the
# supplement on top. jq -S keeps keys sorted so the committed diff is stable.
printf '%s' "$catalog" | jq -S --slurpfile sup "$SUPPLEMENT" '
  ( [ to_entries[]
      | select(.value.api != null)
      | { (.key): (.value.api | capture("^[a-zA-Z][a-zA-Z0-9+.-]*://(?<h>[^/:]+)").h) } ]
    | add // {} )
  | with_entries(select(.value | test("[${}]") | not))
  + $sup[0]
' > "$OUT.tmp"

mv "$OUT.tmp" "$OUT"
echo "resolve-provider-hosts: wrote $(jq -r 'length' "$OUT") providers to $OUT" >&2
