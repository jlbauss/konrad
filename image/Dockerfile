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

# uv pinned to a Minor tag — patch releases (0.11.x) flow in on every rebuild
# (incl. CVE fixes), but a 0.12 with breaking CLI/API behaviour requires a
# deliberate bump here. See README → Configuration → "Pinning strategy".
COPY --from=ghcr.io/astral-sh/uv:0.11 /uv /uvx /usr/local/bin/

ENV VIRTUAL_ENV=/opt/venv

RUN uv venv $VIRTUAL_ENV --python /usr/bin/python3 \
    && uv pip install --no-cache \
        --torch-backend=cpu \
        "docling-slim[standard]"

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
    org.opencontainers.image.licenses="GPL-3.0-only" \
    org.opencontainers.image.source="https://github.com/jan-luca-bauss/konrad"

# NODE_ENV=production per Node Docker best-practices §1.
ENV DEBIAN_FRONTEND=noninteractive \
    NODE_ENV=production

# ── apt: tools the agent uses + comfort tools for `konrad shell` users ──────
#
# Required for opencode / entrypoint / the agent's daily work:
#   git, ca-certificates, curl  → opencode internals + entrypoint LM-Studio probe
#   jq                          → JSON tooling (entrypoint + agent)
#   ripgrep, fd-find, bat, tree → opencode's grep/glob/read backends + agent UX
#   gh                          → GitHub CLI; high-utility when working on a repo
#
# Skill-adjacent (kept now because the future skill rebuild will need them):
#   python3                     → Python interpreter for skill scripts (and uv's target)
#   pandoc                      → document conversion across skills
#   poppler-utils               → pdftotext / pdftoppm / pdfinfo
#
# Comfort tools for interactive `konrad shell` sessions only:
#   less, procps, fzf, zsh, man-db, unzip, gnupg2, nano, htop,
#   iproute2, dnsutils
RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl jq ca-certificates \
    ripgrep fd-find bat tree gh \
    python3 pandoc poppler-utils libgl1 libglib2.0-0 \
    libgomp1 \
    less procps fzf zsh man-db unzip gnupg2 nano htop \
    iproute2 dnsutils \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /var/log/apt/* /var/log/dpkg.log

# Debian renames fd → fdfind and bat → batcat; symlink to canonical names.
RUN ln -sf /usr/bin/fdfind /usr/local/bin/fd \
    && ln -sf /usr/bin/batcat /usr/local/bin/bat

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
# Installing at build time seeds the konrad-npm-global named volume so
# opencode doesn't pull from npm at startup. Updates via `konrad rebuild`.


RUN npm install -g npm@latest opencode-ai@latest \
    && npm cache clean --force

USER node

# ── Frequently-changing content — always last ────────────────────────────────
# opencode/ contains agents/, skills/, and instructions.md. All change often
# but are cheap to copy. Keeping them last means edits here never invalidate
# the npm layer above.
COPY --chown=node:node opencode/ /home/node/.config/opencode/

ENTRYPOINT ["/usr/local/bin/konrad-entrypoint"]
