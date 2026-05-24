#!/usr/bin/env bash
# Snapshot the as-built image's package state into
# /etc/konrad/build-manifest.json. Run from the Dockerfile after every
# install step so the manifest reflects what actually shipped, not what
# the Dockerfile asked for.
#
# Usage: build-manifest.sh <konrad-version> <git-sha> [<build-date>]
#
# build-date defaults to the git commit's author date if passed in,
# falling back to the current UTC time. Sourcing it from the commit
# rather than `date` at build time is what lets this layer cache across
# daily CI rebuilds — two builds from the same source commit produce a
# byte-identical manifest, so the layer hash matches, so users don't
# re-pull it.
#
# The output is what makes the floating-pins strategy honest: when a user
# reports "worked yesterday, broken today," diffing two dated tags'
# manifests names the regression.
set -euo pipefail

KONRAD_VERSION="${1:-unknown}"
GIT_SHA="${2:-unknown}"
BUILD_DATE="${3:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

mkdir -p /etc/konrad

# jq -n with --argjson lets us compose the manifest from multiple
# JSON-emitting commands without string-escaping pain.
jq -n \
  --arg konrad_version "$KONRAD_VERSION" \
  --arg git_sha        "$GIT_SHA" \
  --arg build_date     "$BUILD_DATE" \
  --arg node           "$(node --version)" \
  --arg npm            "$(npm --version)" \
  --arg python         "$(python3 --version)" \
  --arg uv             "$(uv --version)" \
  --arg typst          "$(typst --version 2>&1 | head -n1)" \
  --argjson apt        "$(dpkg-query -W -f='{"name":"${Package}","version":"${Version}"}\n' \
                          | jq -s 'sort_by(.name)')" \
  --argjson npm_global "$(npm ls -g --json --depth=0 2>/dev/null \
                          | jq '.dependencies // {}')" \
  --argjson python_pkgs "$(uv pip list --python /opt/venv/bin/python --format=json \
                            | jq 'sort_by(.name)')" \
  '{
     konrad: {
       version:    $konrad_version,
       git_sha:    $git_sha,
       build_date: $build_date
     },
     tooling: {
       node:   $node,
       npm:    $npm,
       python: $python,
       uv:     $uv,
       typst:  $typst
     },
     apt:        $apt,
     npm_global: $npm_global,
     python:     $python_pkgs
   }' > /etc/konrad/build-manifest.json

printf 'build-manifest: wrote /etc/konrad/build-manifest.json (%d apt, %d python)\n' \
  "$(jq '.apt | length'    /etc/konrad/build-manifest.json)" \
  "$(jq '.python | length' /etc/konrad/build-manifest.json)" >&2
