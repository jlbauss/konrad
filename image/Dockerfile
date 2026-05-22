# =============================================================================
# Stage 1 — python-base
# Installs the Python toolchain and docling into /opt/venv.
# No repo files. Invalidated only when Python deps change.
# =============================================================================
FROM node:26-trixie-slim AS python-base

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates python3 libgl1 libglib2.0-0 libgomp1 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /var/log/apt/* /var/log/dpkg.log

# uv pinned to a minor tag — patch releases (0.11.x) flow in on every rebuild
# (incl. CVE fixes), but a 0.12 with breaking CLI/API behaviour requires a
# deliberate bump here.
COPY --from=ghcr.io/astral-sh/uv:0.11 /uv /uvx /usr/local/bin/

ENV VIRTUAL_ENV=/opt/venv

# onnxruntime is rapidocr's inference engine. docling-slim[standard]
# pulls in rapidocr>=3.8, which leaves the engine choice to the installer
# (RapidOCR 3.x supports ONNX Runtime / OpenVINO / PaddleOCR / PyTorch).
# Without onnxruntime the EXTRACT route's --ocr-engine rapidocr path
# raises "onnxruntime not installed" the first time OCR is needed.
RUN uv venv $VIRTUAL_ENV --python /usr/bin/python3 \
    && uv pip install --no-cache \
    --torch-backend=cpu \
    "docling-slim[standard]" openpyxl pandas \
    pypdf pdfplumber pdf2image reportlab \
    onnxruntime

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
FROM node:26-trixie-slim

LABEL org.opencontainers.image.title="konrad" \
    org.opencontainers.image.description="Sandboxed opencode for local agent models, preloaded with instructions and a curated tool set." \
    org.opencontainers.image.licenses="AGPL-3.0-only" \
    org.opencontainers.image.source="https://gitlab.git.nrw/jbauss2/konrad"

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

# Install Typst
ARG TYPST_VERSION=v0.14.2
ARG TARGETARCH

RUN set -eux; \
    case "$TARGETARCH" in \
      amd64) ARCH="x86_64-unknown-linux-musl" ;; \
      arm64) ARCH="aarch64-unknown-linux-musl" ;; \
      *) echo "unsupported arch: $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://github.com/typst/typst/releases/download/${TYPST_VERSION}/typst-${ARCH}.tar.xz" \
      | tar -xJ --strip-components=1 -C /usr/local/bin "typst-${ARCH}/typst"; \
    chmod +x /usr/local/bin/typst; \
    typst --version

# ── Pull in the Python world from the build stages ──────────────────────────
# venv stays at /opt/venv (same path as in python-base) so all shebang lines
# and absolute references inside the venv remain valid. The model cache uses
# --chown directly so the ~2 GB of model files land with correct ownership in
# a single layer — a subsequent `chown -R` would duplicate them in image history.
COPY --from=python-base               /opt/venv  /opt/venv
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
# few downstream layers as possible. instructions.md is NOT here — it moves
# to opencode/ below so edits to it never touch the npm layer.
COPY merge-config.js   /etc/konrad/merge-config.js
COPY entrypoint.sh     /usr/local/bin/konrad-entrypoint
COPY konrad-defaults/  /etc/konrad/

ENV NODE_OPTIONS=--max-old-space-size=4096 \
    PATH="/opt/venv/bin:/home/node/.npm-global/bin:/home/node/.local/bin:$PATH" \
    NODE_PATH=/usr/local/lib/node_modules

WORKDIR /workspace

ARG CACHE_BUST=1

# ── npm: install opencode ────────────────────────────────────────────────────
# Installed as root into /home/node/.npm-global so the runtime user can't
# mutate it. Lands in the image layer (no named volume backs it), so updates
# flow through `konrad rebuild`. CACHE_BUST above lets the CLI force a refresh
# without changing any source files.
RUN npm install -g npm@latest opencode-ai@latest \
    && npm cache clean --force

USER node

# ── Frequently-changing content — always last ────────────────────────────────
# opencode/ contains agents/, skills/, and instructions.md. All change often
# but are cheap to copy. Keeping them last means edits here never invalidate
# the npm layer above.
COPY --chown=node:node opencode/ /home/node/.config/opencode/

ENTRYPOINT ["/usr/local/bin/konrad-entrypoint"]
