# =============================================================================
# Pinning surface — two categories, both lock-managed except apt.
# See README "Pinning strategy" for the full rationale.
#
#   1. Locked in image/locks/ (committed; resolve-locks bot on GitLab
#      re-resolves daily and opens an MR when any lock moves):
#        - base    (locks/base.lock: full ref node:26-trixie-slim@sha256:…)
#        - uv      (locks/uv.lock:  full ref ghcr.io/astral-sh/uv@sha256:…)
#        - python  (locks/python.lock from locks/python.spec)
#        - npm     (locks/npm.lock: opencode-ai; npm itself comes from
#                   the base image, already pinned by base.lock)
#        - typst   (locks/typst.lock: pinned version string)
#      Each lock keys exactly one Dockerfile layer (or the FROM chain for
#      base); Docker's layer cache reuses the layer when the lock didn't
#      move. Local `konrad rebuild` and CI both read the same locks, so
#      they resolve to the same digests — no drift.
#
#      To major-bump a locked image (e.g., node:26 → node:27), edit the
#      `:tag` part of the lock by hand; the bot resolves the new digest
#      on its next run.
#
#   2. Floating (no lock):
#        - apt packages — cache invalidates only when the base FROM moves
#                          (i.e., when base.lock bumps); so apt naturally
#                          refreshes whenever Debian/Node ship a new
#                          base, picking up the latest package index at
#                          that point. No separate apt lock needed.
#
# When you add or remove a pin, update both this block *and* the README
# table so the two stay in sync.
# =============================================================================
ARG BASE_IMAGE
ARG UV_IMAGE

# =============================================================================
# Stage alias — uv source image
# BuildKit doesn't allow ARG expansion directly in `COPY --from=${ARG}`,
# but it DOES allow it in `FROM ${ARG} AS <name>`. So we alias the
# digest-pinned uv image as a stage and reference the stage name below.
# (The error if you try `COPY --from=${UV_IMAGE}` is explicit: "variable
# expansion is not supported for --from, define a new stage with FROM
# using ARG from global scope as a workaround".)
# =============================================================================
FROM ${UV_IMAGE} AS uv-source

# =============================================================================
# Stage 1 — python-base
# Installs the Python toolchain and docling into /opt/venv.
# No repo files. Invalidated only when Python deps change.
# =============================================================================
FROM ${BASE_IMAGE} AS python-base

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates python3 libgl1 libglib2.0-0 libgomp1 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /var/log/apt/* /var/log/dpkg.log

# uv source image is pinned by digest via locks/uv.lock (the `uv-source`
# stage alias above). The bot bumps it daily when astral-sh ships a new
# uv release; the smoke test gate is the safety net for any breaking change.
COPY --from=uv-source /uv /uvx /usr/local/bin/

ENV VIRTUAL_ENV=/opt/venv

# Install from python.lock — a fully-resolved set with exact versions
# for every transitive dep. Source spec at locks/python.spec; the daily
# resolve-locks CI workflow re-resolves and PRs an updated lock when
# upstream moves. onnxruntime is in the spec because docling-slim's
# rapidocr>=3.8 leaves the inference engine choice to the installer
# (RapidOCR 3.x supports ONNX / OpenVINO / Paddle / PyTorch); without it
# the EXTRACT route's --ocr-engine rapidocr path raises "onnxruntime
# not installed" the first time OCR is needed.
COPY locks/python.lock /tmp/python.lock
RUN uv venv $VIRTUAL_ENV --python /usr/bin/python3 \
    && uv pip install --no-cache --torch-backend=cpu -r /tmp/python.lock \
    && rm /tmp/python.lock

# =============================================================================
# Stage 2 — python-models
# Downloads Docling models into /opt/models.
# No repo files. Invalidated only when Stage 1 changes.
# =============================================================================
FROM python-base AS python-models

RUN mkdir -p /opt/models \
    && /opt/venv/bin/docling-tools models download -o "/opt/models"
# =============================================================================
# Stage 3 — final runtime image
# =============================================================================
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.title="konrad" \
    org.opencontainers.image.description="Sandboxed opencode for local agent models, preloaded with instructions and a curated tool set." \
    org.opencontainers.image.licenses="AGPL-3.0-only" \
    org.opencontainers.image.source="https://gitlab.git.nrw/jbauss2/konrad"

# Version + revision labels and build-manifest live at the very tail of
# this stage. They depend on build-args that change every commit (GIT_SHA,
# BUILD_DATE), so placing them last keeps every layer above (apt, fonts,
# typst, COPY --from, npm, opencode/) cache-stable across commits.

# NODE_ENV=production per Node Docker best-practices §1.
# LANG/LC_ALL force a UTF-8 locale at runtime. Without this, the image
# defaults to POSIX/C, which makes Python's open() and many shell tools
# (awk, sort, wc -m, …) treat files as ASCII or a system-dependent encoding
# — the silent root cause of "why did my CSV come back as mojibake". The
# C.UTF-8 locale ships in Debian trixie without needing the locales pkg.
ENV DEBIAN_FRONTEND=noninteractive \
    NODE_ENV=production \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# ── apt: tools the agent uses + comfort tools for `konrad shell` users ──────
#
# Core (opencode internals + the agent's daily work):
#   git, ca-certificates, curl  → opencode internals + outbound HTTP
#   jq                          → JSON tooling (entrypoint config merge + agent)
#   ripgrep, fd-find, bat, tree → opencode's grep/glob/read backends + agent UX
#   gh                          → GitHub CLI; high-utility when working on a repo
#
# Bundled skills depend on these:
#   python3                     → Python interpreter for skill scripts
#   poppler-utils               → pdftotext / pdftoppm / pdfinfo / pdfimages
#                                 (used by the pdf skill for rasterization and
#                                 raw image extraction; also backs pdf2image)
#   pandoc                      → document conversion, kept available for skills
#                                 that need cross-format text transforms
#
# Comfort tools for interactive `konrad shell` sessions only:
#   less, procps, fzf, zsh, man-db, unzip, gnupg2, nano, htop,
#   iproute2, dnsutils
RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl jq ca-certificates xz-utils \
    ripgrep fd-find bat tree gh \
    python3 pandoc poppler-utils libgl1 libglib2.0-0 \
    libgomp1 libreoffice-nogui \
    less procps fzf zsh man-db unzip gnupg2 nano htop \
    iproute2 dnsutils \
    fontconfig \
    fonts-noto-core \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /var/log/apt/* /var/log/dpkg.log

# Debian renames fd → fdfind and bat → batcat; symlink to canonical names.
RUN ln -sf /usr/bin/fdfind /usr/local/bin/fd \
    && ln -sf /usr/bin/batcat /usr/local/bin/bat

# Bundled font palette (all SIL OFL 1.1). Lands in /usr/local/share/fonts/
# so fontconfig picks it up alongside system fonts — Playwright, LibreOffice,
# Typst, and anything else fontconfig-aware sees the same set. reportlab
# does not read fontconfig; the registration helper at
# image/opencode/skills/pdf/scripts/font_helpers.py resolves family names
# to file paths under here.
#
# fonts-noto-core (above) stays in for broad non-Latin script coverage
# (Arabic, Devanagari, Cyrillic, Greek, Hebrew, Thai, …); the curated
# palette covers Latin / Cyrillic / Greek. CJK is not covered — see
# image/opencode/skills/pdf/references/fonts.md for the user override path.
#
# Per-family attribution lives in image/fonts/konrad/<family>/LICENSE.txt;
# see NOTICE for the consolidated list.
COPY fonts/konrad/ /usr/local/share/fonts/konrad/
RUN fc-cache -f

# Install Typst — version comes from locks/typst.lock so layer caches
# when the lock is unchanged. The daily resolve-locks workflow re-resolves
# from GitHub's releases API and opens a PR when a new version lands.
# Typst is pre-1.0 (so minor bumps can carry breaking changes), but we
# don't ship any .typ templates in this repo — the agent generates Typst
# from scratch each time. Breakage surfaces in the CI smoke test before
# publish.
ARG TARGETARCH
COPY locks/typst.lock /tmp/typst.lock

RUN set -eux; \
    case "$TARGETARCH" in \
      amd64) ARCH="x86_64-unknown-linux-musl" ;; \
      arm64) ARCH="aarch64-unknown-linux-musl" ;; \
      *) echo "unsupported arch: $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    TYPST_VERSION="$(cat /tmp/typst.lock)"; \
    [ -n "$TYPST_VERSION" ] || { echo "locks/typst.lock is empty" >&2; exit 1; }; \
    curl -fsSL "https://github.com/typst/typst/releases/download/v${TYPST_VERSION}/typst-${ARCH}.tar.xz" \
      | tar -xJ --strip-components=1 -C /usr/local/bin "typst-${ARCH}/typst"; \
    chmod +x /usr/local/bin/typst; \
    typst --version; \
    rm /tmp/typst.lock

# ── Pull in the Python world from the build stages ──────────────────────────
# venv stays at /opt/venv (same path as in python-base) so all shebang lines
# and absolute references inside the venv remain valid. The model cache uses
# --chown directly so the model files land with correct ownership in a single
# layer — a subsequent `chown -R` would duplicate them in image history.
# uv comes along too — needed at runtime for `uv pip list` in the build
# manifest script and useful for `uv pip install` extensions.
COPY --from=python-base               /opt/venv  /opt/venv
COPY --from=python-base               /usr/local/bin/uv  /usr/local/bin/uv
COPY --from=python-models --chown=node:node /opt/models  /home/node/.cache/docling/models

ENV VIRTUAL_ENV=/opt/venv \
    DOCLING_ARTIFACTS_PATH=/home/node/.cache/docling/models

# ── XDG-compliant home structure for the node user ──────────────────────────
# `install -d -o node -g node` creates each dir with correct ownership in one
# step, so we never recursively chown the heavy model cache below it. The
# model cache itself was already node-owned at COPY --chown time above.
RUN install -d -o node -g node \
    /workspace \
    /home/node/.npm-global \
    /home/node/.local/share/opencode \
    /home/node/.local/state \
    /home/node/.local/bin \
    /home/node/.cache/opencode \
    /home/node/.config \
    /home/node/.opencode-secrets

# ── Konrad system files (root-owned — node user can't tamper) ───────────────
# Ordered rarest-to-change first so that editing these files invalidates as
# few downstream layers as possible. environment.md is NOT here — it lives
# in opencode/ below so edits to it never touch the npm layer.
COPY merge-config.js   /etc/konrad/merge-config.js
COPY entrypoint.sh     /usr/local/bin/konrad-entrypoint
COPY konrad-defaults/  /etc/konrad/

ENV NODE_OPTIONS=--max-old-space-size=4096 \
    PATH="/opt/venv/bin:/home/node/.npm-global/bin:/home/node/.local/bin:$PATH" \
    NODE_PATH=/usr/local/lib/node_modules

WORKDIR /workspace

# ── npm: install opencode ────────────────────────────────────────────────────
# Installed as root into /home/node/.npm-global so the runtime user can't
# mutate it. The opencode-ai version comes from locks/npm.lock so this
# layer caches when the lock is unchanged. npm itself is whatever the
# base image ships — base.lock already pins the base image by digest,
# so the bundled npm is deterministic; pinning it again here was
# belt-and-suspenders, and every weekly npm release used to bust this
# layer's cache for no real benefit. The daily resolve-locks workflow
# re-queries the npm registry and opens a PR when opencode-ai bumps.
COPY locks/npm.lock /tmp/npm.lock
RUN OPENCODE_VERSION="$(jq -r '."opencode-ai"' /tmp/npm.lock)" \
    && npm install -g "opencode-ai@${OPENCODE_VERSION}" \
    && npm cache clean --force \
    && rm /tmp/npm.lock

# ── Frequently-changing content (cache-stable across non-opencode commits) ──
# opencode/ contains agents/, skills/, and environment.md. They change
# often but only on commits that actually edit them. Placed BEFORE the
# version labels + build manifest so a commit that doesn't touch
# opencode/ (a ROADMAP update, a CI tweak, anything outside image/opencode/)
# leaves this layer's diff_id stable — users pulling :latest after such
# a commit don't re-download these files.
COPY --chown=node:node opencode/ /home/node/.config/opencode/

# ── Version labels + build manifest ─────────────────────────────────────────
# Declared at the very tail on purpose. All three build-args change per
# commit: KONRAD_VERSION on a version bump, GIT_SHA on every commit,
# BUILD_DATE on every commit (the git commit's author date — same commit
# → same date, so re-runs on the same SHA produce a byte-identical
# manifest layer and cache-hit). If these ARGs sat near the top of the
# stage, the LABEL using them would invalidate every downstream RUN on
# every commit. Keeping the only references here means every commit
# churns just these tail layers (a few KB) — apt, fonts, typst,
# COPY --from, npm, and opencode/ all cache-stable above.
#
# The labels are the cheap source for `konrad version` — readable from
# `podman image inspect` without starting a container. The full build
# manifest (apt/npm/python snapshots) lives at /etc/konrad/build-manifest.json
# inside the image for the rare deep-dive (`konrad version --manifest`).
# Two purposes: (1) diagnose "worked yesterday, broken today" by diffing
# manifests between dated tags; (2) make the floating-pins strategy
# honest — even if pins float, what shipped is always knowable.
ARG KONRAD_VERSION=dev
ARG GIT_SHA=unknown
ARG BUILD_DATE=unknown
LABEL org.opencontainers.image.version="${KONRAD_VERSION}" \
    org.opencontainers.image.revision="${GIT_SHA}" \
    org.opencontainers.image.created="${BUILD_DATE}"
COPY build-manifest.sh /tmp/build-manifest.sh
RUN bash /tmp/build-manifest.sh "$KONRAD_VERSION" "$GIT_SHA" "$BUILD_DATE" \
    && rm /tmp/build-manifest.sh

USER node

ENTRYPOINT ["/usr/local/bin/konrad-entrypoint"]
