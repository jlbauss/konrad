#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Build the konrad container image to konrad:local — the single source of
# truth for the local build, which `konrad-dev rebuild` also delegates to.
# Usable without having the CLI installed yet. (The :latest / :0.x / :<sha>
# tags are CI-only; this convenience build never writes them.)
#
# The Dockerfile builds these stages (plus uv-source, a plain image pull):
#   python-base   — Python venv + docling-slim (no repo files)
#   python-models — Docling model download     (no repo files)
#   venv-split    — the venv partitioned into three COPY layers
#   skills        — upstream skills at their pinned commits (a quick fetch)
#   final         — full runtime image
#
# We tag the three slow intermediate stages so Podman's layer cache keeps them
# alive across `podman system prune` / `podman image prune`. Without tags
# those stages are treated as dangling and get collected, forcing a full
# model re-download on the next build.
#
# A rebuild only moves a tag, so the image it pointed at stays behind with
# its parent chain (several GB per rebuild); the Podman path below removes
# those once the build is done, and the leftovers of interrupted builds.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CTX="$REPO_ROOT/image"

# Build engine. Normally Podman/buildah (CI, Linux, `konrad code --nested`). On the
# apple/container runtime we build with `container build` instead — its
# BuildKit-based builder lands the image straight in container's own store, so a
# Mac contributor needs neither podman nor its machine VM. bin/konrad's
# do_rebuild exports the detected engine; run standalone, it defaults to podman
# (the CI/Linux path). Lock reading + build metadata below are shared; only the
# build invocation itself differs.
ENGINE="${KONRAD_ENGINE:-podman}"
case "$ENGINE" in
  podman|container) ;;
  *) printf 'konrad-build: KONRAD_ENGINE must be podman or container (got %s)\n' "$ENGINE" >&2; exit 1 ;;
esac

# Pinned image refs (full name@digest). CI reads the same locks, so
# local builds resolve to the same base + uv as the published image.
BASE_IMAGE="$(cat "$CTX/locks/base.lock" 2>/dev/null)" \
  || { printf 'konrad-build: missing %s\n' "$CTX/locks/base.lock" >&2; exit 1; }
UV_IMAGE="$(cat "$CTX/locks/uv.lock" 2>/dev/null)" \
  || { printf 'konrad-build: missing %s\n' "$CTX/locks/uv.lock" >&2; exit 1; }
[ -n "$BASE_IMAGE" ] \
  || { printf 'konrad-build: empty %s\n' "$CTX/locks/base.lock" >&2; exit 1; }
[ -n "$UV_IMAGE" ] \
  || { printf 'konrad-build: empty %s\n' "$CTX/locks/uv.lock" >&2; exit 1; }

# Build metadata baked into the image manifest + OCI labels.
KONRAD_VERSION="$(cat "$REPO_ROOT/VERSION" 2>/dev/null || printf 'dev')"
GIT_SHA="$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || printf 'unknown')"
# Commit author date drives BUILD_DATE in build-manifest.json so rebuilds
# from the same source commit produce a byte-identical manifest layer.
BUILD_DATE="$(git -C "$REPO_ROOT" log -1 --format=%cI HEAD 2>/dev/null \
              | sed 's/+00:00/Z/' \
              | sed 's/T\(..\):\(..\):\(..\).*/T\1:\2:\3Z/' \
              || date -u +%Y-%m-%dT%H:%M:%SZ)"

# apple/container path — one BuildKit invocation. BuildKit caches intermediate
# stages internally, so the podman-only intermediate-stage cache-tagging below
# (which guards buildah's dangling-layer collection) isn't needed or supported
# here. Output defaults to type=oci, loading straight into container's image
# store. TARGETARCH is set automatically by BuildKit from the native platform
# (apple/container is Apple-Silicon-only). The hf_token secret is optional and
# omitted locally, exactly as on the podman path (anonymous, rate-limited pull).
if [ "$ENGINE" = container ]; then
  command -v container >/dev/null 2>&1 \
    || { printf 'konrad-build: the container CLI is not installed.\n' >&2; exit 1; }
  # apple/container caps the Dockerfile at 16 KiB (apple/container#735); ours is
  # ~27 KiB, almost all rationale comments. Strip full-line comments + blank
  # lines into a temp Containerfile for THIS build only — the committed
  # image/Dockerfile stays the documented source of truth. Safe: a Dockerfile
  # only treats '#' as a comment at the start of a line, and none of ours sit
  # inside a '\' continuation (asserted), so the instruction stream is identical
  # to what podman builds; BuildKit ignores comments anyway, so layers and
  # caching are unaffected. Stripped size is ~7 KiB, well under the cap.
  df_tmp="$(mktemp "${TMPDIR:-/tmp}/konrad-dockerfile.XXXXXX")"
  trap 'rm -f "$df_tmp"' EXIT
  grep -vE '^[[:space:]]*(#|$)' "$CTX/Dockerfile" > "$df_tmp"
  printf 'konrad-build: building konrad:local with container build (konrad=%s sha=%s)…\n' \
    "$KONRAD_VERSION" "$GIT_SHA"
  status=0
  container build \
    --build-arg "BASE_IMAGE=$BASE_IMAGE" \
    --build-arg "UV_IMAGE=$UV_IMAGE" \
    --build-arg "KONRAD_VERSION=$KONRAD_VERSION" \
    --build-arg "GIT_SHA=$GIT_SHA" \
    --build-arg "BUILD_DATE=$BUILD_DATE" \
    -t konrad:local \
    -f "$df_tmp" \
    "$CTX" || status=$?
  exit "$status"
fi

# Podman/buildah path (CI, Linux, `konrad code --nested`, and Macs pinned to podman).
command -v podman >/dev/null 2>&1 \
  || { printf 'konrad-build: podman is not installed.\n' >&2; exit 1; }

# An interrupted build (Ctrl-C, SIGTERM, a SIGKILL from the OOM killer or a
# stopped session) leaves its buildah working containers in storage, where
# they pin their images for good; --force-rm only covers a failing step.
# Remove those older than a day: no build runs that long, so a build running
# right now elsewhere in a shared store keeps its own. Other engines'
# containers in the store list as `storage`, never `buildah`, and stay. Not
# `--filter until`, which podman ignores for storage containers; `--force`
# because a killed build's containers still count as mounted.
cutoff=$(( $(date +%s) - 86400 ))
podman ps -a --external --format '{{.ID}} {{.Created.Unix}} {{.Command}}' 2>/dev/null \
  | while read -r id created cmd; do
      if [ "$cmd" = buildah ] && [ "$created" -lt "$cutoff" ]; then
        podman rm --storage --force "$id" >/dev/null 2>&1 || true
      fi
    done || true

# Remember what each tag points at now, and remove those images once this
# run is over (also when it fails partway, for the tags it already moved).
# Only an image no tag points at any more goes (an rmi by ID would delete a
# tagged one too). `podman rmi` takes the parents nothing else uses with it
# and keeps layers the new images share; it fails, harmlessly, on an image a
# container still uses. Newest first, so a parent goes after its children.
TAGS="konrad:local konrad-venv-split:cache konrad-python-models:cache konrad-python-base:cache"
old_ids=""
for tag in $TAGS; do
  old_ids="$old_ids $(podman image inspect --format '{{.Id}}' "$tag" 2>/dev/null || true)"
done
remove_replaced() {
  for id in $old_ids; do
    if [ "$(podman image inspect --format '{{len .RepoTags}}' "$id" 2>/dev/null)" = 0 ]; then
      podman rmi "$id" >/dev/null 2>&1 || true
    fi
  done
}
trap remove_replaced EXIT

printf 'konrad-build: building python-base (Python venv + docling-slim)…\n'
podman build --target python-base \
  --build-arg "BASE_IMAGE=$BASE_IMAGE" \
  --build-arg "UV_IMAGE=$UV_IMAGE" \
  -t konrad-python-base:cache "$CTX"

printf 'konrad-build: building python-models (Docling model download)…\n'
podman build --target python-models \
  --build-arg "BASE_IMAGE=$BASE_IMAGE" \
  --build-arg "UV_IMAGE=$UV_IMAGE" \
  -t konrad-python-models:cache "$CTX"

printf 'konrad-build: building venv-split (the venv in three layers)…\n'
podman build --target venv-split \
  --build-arg "BASE_IMAGE=$BASE_IMAGE" \
  --build-arg "UV_IMAGE=$UV_IMAGE" \
  -t konrad-venv-split:cache "$CTX"

printf 'konrad-build: building final runtime image konrad:local (konrad=%s sha=%s)…\n' \
  "$KONRAD_VERSION" "$GIT_SHA"
podman build \
  --build-arg "BASE_IMAGE=$BASE_IMAGE" \
  --build-arg "UV_IMAGE=$UV_IMAGE" \
  --build-arg "KONRAD_VERSION=$KONRAD_VERSION" \
  --build-arg "GIT_SHA=$GIT_SHA" \
  --build-arg "BUILD_DATE=$BUILD_DATE" \
  -t konrad:local "$CTX"
