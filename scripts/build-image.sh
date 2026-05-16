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

printf 'konrad-build: building python-base (Python venv + docling-slim)…\n'
podman build --target python-base  -t konrad-python-base:cache  "$CTX"

printf 'konrad-build: building python-models (Docling model download)…\n'
podman build --target python-models -t konrad-python-models:cache "$CTX"

printf 'konrad-build: building final runtime image…\n'
exec podman build -t konrad:latest "$CTX"
