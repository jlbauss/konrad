#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Host-side probe for bin/konrad's resumable pull fallback on Apple's
# `container` (container_pull_resumable; ROADMAP → Upstream workarounds). Run it
# on a Mac, from a checkout, with the container service running:
#
#   ./scripts/probe-container-pull.sh [image]     # default ghcr.io/jlbauss/konrad:latest
#
# 1. Baseline: the service answers, the registry answers with its auth
#    challenge, and the fallback's tools are there — so a failure later is the
#    fallback's, not the environment's.
# 2. Its smallest layers above 5 MB, about PROBE_MB in all, are hidden from the
#    fallback's view of the content store (a stand-in store that links every
#    real blob but those), so it has to fetch them even when the store holds
#    the whole image. The real store is only read.
# 3. The change: eng_pull with `container image pull` forced to fail (as a cut
#    download makes it fail), and every blob download cut after PROBE_CUT
#    seconds at PROBE_RATE, so the fallback has to resume. It must fetch the
#    hidden layers, load the image, and leave no partial state.
# 4. The loaded image runs.
#
# It loads the image under its registry name, as `konrad update` would, and
# leaves the konrad:latest tag alone. State goes to a temp dir, not ~/.local.
# Knobs: PROBE_MB (100), PROBE_CUT (20 s), PROBE_RATE (2M per second).
set -euo pipefail

IMAGE="${1:-ghcr.io/jlbauss/konrad:latest}"
KONRAD="$(cd "$(dirname "$0")/.." && pwd)/bin/konrad"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'ok:   %s\n' "$*"; }

[[ "$(uname -s)" == Darwin ]] || fail "run this on a Mac with Apple's container"
container system status >/dev/null 2>&1 || fail "the container service isn't running: container system start"
pass "container service answers"
curl -sS -o /dev/null -D - "https://${IMAGE%%/*}/v2/" | tr -d '\r' \
  | grep -i '^www-authenticate: Bearer' >/dev/null || fail "${IMAGE%%/*} gave no auth challenge"
pass "${IMAGE%%/*} answers with its auth challenge"
for t in curl jq tar shasum; do command -v "$t" >/dev/null || fail "$t missing"; done
pass "curl, jq, tar and shasum present"

XDG_STATE_HOME="$(mktemp -d)"
export XDG_STATE_HOME KONRAD_ENGINE=container KONRAD_SOURCE_ONLY=1
cuts="$XDG_STATE_HOME/cuts"
: >"$cuts"
# shellcheck source=/dev/null
source "$KONRAD"

# The layers to hide: the host platform's manifest, read from the registry.
host="${IMAGE%%/*}" repo="${IMAGE#*/}"
tag="${repo##*:}" repo="${repo%:*}"
digest="$(_registry_curl "$host" "$repo" -s \
  -H "Accept: application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json" \
  "https://$host/v2/$repo/manifests/$tag" | jq -r --arg a "$(_pull_arch)" \
  '[.manifests[] | select(.platform.os == "linux" and .platform.architecture == $a)][0].digest')"
hide="$(_registry_curl "$host" "$repo" -s -H "Accept: application/vnd.oci.image.manifest.v1+json" \
  "https://$host/v2/$repo/manifests/$digest" | jq -r --argjson max "$(( ${PROBE_MB:-100} * 1048576 ))" '
    [.layers[] | select(.size >= 5242880)] | sort_by(.size)
    | reduce .[] as $l ([]; if (map(.size) | add // 0) < $max then . + [$l] else . end)
    | .[].digest | ltrimstr("sha256:")')"
[[ -n "$hide" ]] || fail "found no layer to hide in $IMAGE's manifest"
real="$(container system status | _status_field paths.appRoot)"
real="${real%/}/content/blobs/sha256"
[[ -d "$real" ]] || fail "no content store at $real"
fake="$XDG_STATE_HOME/store"
mkdir -p "$fake/content/blobs/sha256"
hidden=" $(tr '\n' ' ' <<<"$hide")"
for f in "$real"/*; do
  case "$hidden" in *" ${f##*/} "*) ;; *) ln -s "$f" "$fake/content/blobs/sha256/${f##*/}" ;; esac
done
pass "hid $(wc -w <<<"$hide" | tr -d ' ') layers of $IMAGE from the fallback's view of the store"

# The pull fails, as a cut download makes it fail, and the status names the
# stand-in store; everything else is the engine.
container() {
  case "$1 ${2:-}" in
    "image pull") echo "probe: pull forced to fail" >&2; return 1 ;;
    "system status") command container system status | sed "s|^\(paths.appRoot[[:space:]]*\).*|\1$fake/|" ;;
    *) command container "$@" ;;
  esac
}
# Every blob download stops after PROBE_CUT seconds, as the CDN cuts a slow one.
curl() {
  local a
  for a in "$@"; do
    if [[ "$a" == */blobs/* ]]; then
      command curl --max-time "${PROBE_CUT:-20}" --limit-rate "${PROBE_RATE:-2M}" "$@" && return 0
      echo cut >>"$cuts"
      return 28
    fi
  done
  command curl "$@"
}

eng_pull "$IMAGE" || fail "eng_pull failed (output above)"
[[ -s "$cuts" ]] || fail "no download was cut: lower PROBE_CUT or PROBE_RATE so the probe exercises a resume"
pass "eng_pull loaded $IMAGE after $(wc -l <"$cuts" | tr -d ' ') cut downloads"
[[ ! -e "$XDG_STATE_HOME/konrad/pull" ]] || fail "the fallback left $XDG_STATE_HOME/konrad/pull behind"
pass "no partial state left"
rm -rf "$XDG_STATE_HOME"

command container run --rm --entrypoint /bin/ls "$IMAGE" /etc/konrad | grep build-manifest.json >/dev/null \
  || fail "the loaded image doesn't run"
pass "the loaded image runs: $(eng_image_label "$IMAGE" org.opencontainers.image.revision)"
printf 'PASS\n'
