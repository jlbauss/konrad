#!/usr/bin/env bash
# Build the konrad container image. Same as `konrad rebuild`, just
# usable without having the CLI installed yet.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
exec podman build -t konrad:latest "$REPO_ROOT/image"
