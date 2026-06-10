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

# --- 8. Org config layer: entrypoint composes baked < org < user ---
# Unlike the checks above, this RUNS the real entrypoint (not --entrypoint "")
# with org/ and user/ layers bind-mounted, then inspects the composed config.
# /workspace is baked node-owned, so the entrypoint's .agent bootstrap works
# without a workspace mount. ':ro,z' relabels for SELinux hosts (Fedora local
# podman) and is accepted/ignored by docker in CI.
info "org config layer (entrypoint compose)"
# Remote daemon (dev-container self-testing — KONRAD_REMOTE_HOST_ROOT set): the
# bind-mount sources below resolve on the DAEMON's filesystem, not this script's,
# so a local mktemp dir is invisible daemon-side (statfs ENOENT). The real konrad
# self-test path skips the config-layer mounts for exactly this reason (podman_run
# in bin/konrad), and CI exercises this compose logic on every build against a
# local daemon — so skip here rather than fail. Matches CONTRIBUTING.md.
if [[ -n "${KONRAD_REMOTE_HOST_ROOT:-}" ]]; then
  printf '  \033[33mSKIP\033[0m  org-layer compose (remote daemon — covered by CI on a local daemon)\n'
else
ORG_TMP="$(mktemp -d)"
USER_TMP="$(mktemp -d)"
cleanup_org() { rm -rf "$ORG_TMP" "$USER_TMP"; }
trap cleanup_org EXIT
# Org layer: an internal provider + declared model, an AGENTS.md, and a skill.
cat > "$ORG_TMP/opencode.jsonc" <<'JSON'
{ "provider": { "acme": { "npm": "@ai-sdk/openai-compatible", "name": "ACME (org)", "models": { "m1": { "name": "M1" } } } } }
JSON
printf '# org rules\n' > "$ORG_TMP/AGENTS.md"
mkdir -p "$ORG_TMP/skills/house-style"
printf -- '---\nname: house-style\ndescription: example\n---\n# House\n' \
  > "$ORG_TMP/skills/house-style/SKILL.md"
# User layer: override the org provider's display name — the user must win.
cat > "$USER_TMP/opencode.jsonc" <<'JSON'
{ "provider": { "acme": { "name": "ACME (user override)" } } }
JSON
# mktemp -d makes dirs 0700. The smoke test doesn't use --userns=keep-id (it
# must also run under docker in CI), so the container's `node` uid isn't the
# owner of these host dirs and couldn't traverse 0700. Open them up so the
# bind mounts are readable regardless of uid mapping (',z' below handles
# SELinux separately). Real konrad doesn't need this — keep-id maps the host
# user to node so its own ~/.config/konrad files are readable as-is.
chmod -R a+rX "$ORG_TMP" "$USER_TMP"
# The in-container assertions are a quoted heredoc fed to `bash -s` on stdin
# (-i keeps stdin open) — quoted so the $cfg / $(...) below are the container
# shell's, not this script's.
"$ENGINE" run --rm -i \
  -v "$ORG_TMP:/home/node/.config/konrad/org:ro,z" \
  -v "$USER_TMP:/home/node/.config/konrad/user:ro,z" \
  "$IMAGE" bash -s <<'CONTAINER' || fail "org-layer compose/precedence/instructions/skill assertion failed"
set -e
cfg=/home/node/.config/opencode/opencode.jsonc
# org provider + model merged in
jq -e '.provider.acme.models.m1' "$cfg" >/dev/null
# baked default survived the merge (proves the fold, not a clobber)
jq -e '.provider.lmstudio' "$cfg" >/dev/null
# USER precedence: user override of the name wins over org
[ "$(jq -r '.provider.acme.name' "$cfg")" = "ACME (user override)" ]
# org AGENTS.md appended to .instructions (the system channel)
jq -e '.instructions | index("/home/node/.config/konrad/org/AGENTS.md")' "$cfg" >/dev/null
# org skill copied into the opencode skills dir
test -f /home/node/.config/opencode/skills/house-style/SKILL.md
CONTAINER
pass "org layer merges under user precedence; instructions append; skill loads"
fi

# --- 9. Host-side: flat → user/ config migration (bin/konrad) ---
# Migration lives in bin/konrad (host CLI), not the image. Source it with the
# KONRAD_SOURCE_ONLY=1 test seam so migrate_flat_config runs in isolation
# against a throwaway $HOME.
info "config migration (host-side)"
SMOKE_REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -f "$SMOKE_REPO_ROOT/bin/konrad" ]]; then
  MIG_HOME="$(mktemp -d)"
  mkdir -p "$MIG_HOME/.config/konrad/agents"
  printf '{}\n'      > "$MIG_HOME/.config/konrad/opencode.jsonc"
  printf '# rules\n' > "$MIG_HOME/.config/konrad/AGENTS.md"
  # shellcheck source=/dev/null
  ( HOME="$MIG_HOME" KONRAD_SOURCE_ONLY=1 . "$SMOKE_REPO_ROOT/bin/konrad"
    set +eu; migrate_flat_config >/dev/null 2>&1 )
  test -f "$MIG_HOME/.config/konrad/user/opencode.jsonc" || fail "migration: opencode.jsonc not moved into user/"
  test -d "$MIG_HOME/.config/konrad/user/agents"         || fail "migration: agents/ not moved into user/"
  test -f "$MIG_HOME/.config/konrad/user/AGENTS.md"      || fail "migration: AGENTS.md not moved into user/"
  test ! -e "$MIG_HOME/.config/konrad/opencode.jsonc"    || fail "migration: flat opencode.jsonc still present after move"
  # Idempotent: a second run (user/ now exists) must no-op without error.
  # shellcheck source=/dev/null
  ( HOME="$MIG_HOME" KONRAD_SOURCE_ONLY=1 . "$SMOKE_REPO_ROOT/bin/konrad"
    set +eu; migrate_flat_config >/dev/null 2>&1 )
  test -f "$MIG_HOME/.config/konrad/user/opencode.jsonc" || fail "migration: not idempotent"
  rm -rf "$MIG_HOME"
  pass "flat config migrated into user/ (idempotent)"
else
  printf '  \033[33mSKIP\033[0m  config migration (bin/konrad not found next to smoke-test.sh)\n'
fi

# --- All clear ---
printf '\n\033[32mall checks passed for %s\033[0m\n' "$IMAGE"
