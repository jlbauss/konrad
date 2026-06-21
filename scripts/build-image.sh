#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Build the konrad container image to konrad:local — the single source of
# truth for the local build, which `konrad-dev rebuild` also delegates to.
# Usable without having the CLI installed yet. (The :latest / :0.x / :<sha>
# tags are CI-only; this convenience build never writes them.)
#
# The Dockerfile uses a 3-stage build:
#   python-base   — Python venv + docling-slim (no repo files)
#   python-models — Docling model download     (no repo files)
#   final         — full runtime image
#
# We tag the two intermediate stages so Podman's layer cache keeps them
# alive across `podman system prune` / `podman image prune`. Without tags
# those stages are treated as dangling and get collected, forcing a full
# model re-download on the next build.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CTX="$REPO_ROOT/image"

# Build engine. Normally Podman/buildah (CI, Linux, the dev container). On the
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

# Podman/buildah path (CI, Linux, the dev container, and Macs pinned to podman).
command -v podman >/dev/null 2>&1 \
  || { printf 'konrad-build: podman is not installed.\n' >&2; exit 1; }

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

printf 'konrad-build: building final runtime image konrad:local (konrad=%s sha=%s)…\n' \
  "$KONRAD_VERSION" "$GIT_SHA"
exec podman build \
  --build-arg "BASE_IMAGE=$BASE_IMAGE" \
  --build-arg "UV_IMAGE=$UV_IMAGE" \
  --build-arg "KONRAD_VERSION=$KONRAD_VERSION" \
  --build-arg "GIT_SHA=$GIT_SHA" \
  --build-arg "BUILD_DATE=$BUILD_DATE" \
  -t konrad:local "$CTX"
