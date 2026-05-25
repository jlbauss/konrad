#!/usr/bin/env bash
# Build the konrad container image. Same as `konrad rebuild`, just
# usable without having the CLI installed yet.
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

command -v podman >/dev/null 2>&1 \
  || { printf 'konrad-build: podman is not installed.\n' >&2; exit 1; }

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

printf 'konrad-build: building final runtime image (konrad=%s sha=%s)…\n' \
  "$KONRAD_VERSION" "$GIT_SHA"
exec podman build \
  --build-arg "BASE_IMAGE=$BASE_IMAGE" \
  --build-arg "UV_IMAGE=$UV_IMAGE" \
  --build-arg "KONRAD_VERSION=$KONRAD_VERSION" \
  --build-arg "GIT_SHA=$GIT_SHA" \
  --build-arg "BUILD_DATE=$BUILD_DATE" \
  -t konrad:latest "$CTX"
