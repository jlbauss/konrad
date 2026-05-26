#!/usr/bin/env bash
# Smoke test the konrad image. Runs in CI before publishing to the
# registry — if any check fails, the daily build does not move the
# `:latest` tag and last-known-good keeps serving users. Also runnable
# locally:
#
#   ./scripts/smoke-test.sh                       # tests konrad:latest
#   ./scripts/smoke-test.sh my-tag:1.2            # tests an arbitrary tag
#   CONTAINER_ENGINE=docker ./scripts/smoke-test.sh   # use docker not podman
#
# CONTAINER_ENGINE defaults to podman (matches the local konrad runtime)
# but accepts docker (used in GitHub Actions, where docker is preinstalled
# and podman is not). Both engines accept the same flags we use here
# (`run --rm --entrypoint ""`, `image inspect`).
#
# The checks are deliberately "installed and importable" rather than
# "agent runs end-to-end" — exercising opencode requires a model
# provider, which is user-specific. Catching basic install regressions is
# what makes the float-everything pinning strategy safe.
set -euo pipefail

IMAGE="${1:-konrad:latest}"
ENGINE="${CONTAINER_ENGINE:-podman}"

# --- Output helpers ---
pass() { printf '  \033[32mPASS\033[0m  %s\n' "$*"; }
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$*" >&2; exit 1; }
info() { printf '\n\033[1m%s\033[0m\n' "$*"; }

# Run a one-shot command inside the image, no workspace mount needed.
in_image() { "$ENGINE" run --rm --entrypoint "" "$IMAGE" "$@"; }

info "smoke-testing $IMAGE (engine: $ENGINE)"

# --- 1. Image exists ---
# `image inspect` returns non-zero if the image is missing — works in both
# docker and podman (whereas `image exists` is podman-only).
"$ENGINE" image inspect "$IMAGE" >/dev/null 2>&1 \
  || fail "image $IMAGE not found locally — build or pull it first"
pass "image present"

# --- 2. Core binaries on PATH ---
# Names here MUST match the actual binary names in the image, not the
# Debian package names: ripgrep installs `rg`; fd-find installs `fdfind`
# (Dockerfile symlinks to `fd`); bat installs `batcat` (Dockerfile
# symlinks to `bat`). See image/Dockerfile's apt-get install + symlink
# block.
info "core binaries"
for bin in opencode node npm python3 uv typst jq git rg fd bat tree gh pandoc; do
  in_image which "$bin" >/dev/null \
    || fail "$bin not on PATH"
  pass "$bin"
done

# --- 3. Tool versions print (catches broken installs) ---
info "version probes"
in_image node    --version >/dev/null || fail "node --version failed"
in_image npm     --version >/dev/null || fail "npm --version failed"
in_image python3 --version >/dev/null || fail "python3 --version failed"
in_image uv      --version >/dev/null || fail "uv --version failed"
in_image typst   --version >/dev/null || fail "typst --version failed"
in_image opencode --version >/dev/null || fail "opencode --version failed"
pass "all version probes returned 0"

# --- 4. Python skill deps import ---
# Invoke the venv python directly (not `python3` on PATH) so we are
# guaranteed to hit the docling-bearing interpreter, not the system one.
info "python skill imports"
in_image /opt/venv/bin/python -c '
import docling          # EXTRACT route
import pypdf            # EDIT route
import pdfplumber       # region discovery
import pdf2image        # rasterization
import reportlab        # GENERATE route
import openpyxl, pandas # spreadsheets skill
import onnxruntime      # rapidocr engine
print("ok")
' >/dev/null || fail "python skill imports failed"
pass "docling, pypdf, pdfplumber, pdf2image, reportlab, openpyxl, pandas, onnxruntime"

# --- 5. Build manifest exists and parses ---
info "build manifest"
in_image test -f /etc/konrad/build-manifest.json \
  || fail "/etc/konrad/build-manifest.json missing"
in_image jq -e '.konrad.version, .konrad.build_date, .tooling.node, .apt[0], .python[0]' \
  /etc/konrad/build-manifest.json >/dev/null \
  || fail "manifest JSON missing expected keys"
KONRAD_VER=$(in_image jq -r .konrad.version /etc/konrad/build-manifest.json)
BUILD_DATE=$(in_image jq -r .konrad.build_date /etc/konrad/build-manifest.json)
pass "manifest valid (konrad=$KONRAD_VER, built=$BUILD_DATE)"

# --- 6. Bundled config files in place ---
# Cross-referenced against image/Dockerfile's COPY block. Two distinct
# trees: /etc/konrad/ (root-owned, used by the entrypoint) and
# /home/node/.config/opencode/ (opencode-discoverable, where agents,
# skills, and environment.md live — *not* /etc/konrad/environment.md;
# the Dockerfile keeps it in the opencode-discoverable dir intentionally
# so edits don't invalidate the npm layer).
info "baked content"
# Entrypoint + config-merge machinery
in_image test -x /usr/local/bin/konrad-entrypoint \
  || fail "konrad-entrypoint missing or non-executable"
in_image test -f /etc/konrad/merge-config.js \
  || fail "merge-config.js missing"
in_image test -f /etc/konrad/opencode-defaults.jsonc \
  || fail "opencode-defaults.jsonc missing"
# opencode-discoverable content
in_image test -f /home/node/.config/opencode/environment.md \
  || fail "environment.md missing"
in_image test -f /home/node/.config/opencode/agents/konrad.md \
  || fail "konrad agent missing"
for skill in do-it-manually pdf quality-assurance spreadsheets; do
  in_image test -d "/home/node/.config/opencode/skills/$skill" \
    || fail "$skill skill missing"
done
# Bundled fonts
in_image test -d /usr/local/share/fonts/konrad \
  || fail "bundled fonts missing"
pass "entrypoint, defaults, agents, skills, and fonts present"

# --- 7. End-to-end: docling extracts a tiny PDF ---
# Catches regressions in the docling/onnxruntime/rapidocr chain that
# version probes alone won't detect.
info "docling end-to-end"
in_image bash -c '
set -e
cd /tmp
# Minimal 1-page PDF with the text "smoke" — generated by reportlab so
# we do not depend on having a test fixture in the image. Invoke the
# venv python explicitly so reportlab resolves to the right interpreter.
/opt/venv/bin/python -c "
from reportlab.pdfgen import canvas
c = canvas.Canvas(\"/tmp/smoke.pdf\")
c.drawString(100, 750, \"smoke\")
c.save()
"
docling /tmp/smoke.pdf --to md --output /tmp/out >/dev/null
grep -qi smoke /tmp/out/smoke.md
' || fail "docling round-trip failed"
pass "docling extracted a generated PDF"

# --- All clear ---
printf '\n\033[32mall checks passed for %s\033[0m\n' "$IMAGE"
