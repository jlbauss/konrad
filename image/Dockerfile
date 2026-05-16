FROM node:26-trixie-slim

LABEL org.opencontainers.image.title="konrad" \
    org.opencontainers.image.description="Sandboxed opencode for local agent models, preloaded with instructions and a curated tool set." \
    org.opencontainers.image.licenses="GPL-3.0-only" \
    org.opencontainers.image.source="https://github.com/jan-luca-bauss/konrad"

# NODE_ENV=production per Node Docker best-practices §1: opencode treats
# this as "real run, optimise"; cheap to set and harmless if a dev wants
# to override at podman-run time.
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
# Comfort tools for interactive `konrad shell` sessions only — the agent
# never calls these, but a user shelling in expects them to be there:
#   less, procps, fzf, zsh, man-db, unzip, gnupg2, nano, htop,
#   iproute2, dnsutils
#
# --no-install-recommends keeps us off the "this package and 30 friends"
# rails; apt cleanup happens in-RUN so the layer stays small.
RUN apt-get update && apt-get install -y --no-install-recommends \
    git ca-certificates curl jq \
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

# ── Python toolchain ────────────────────────────────────────────────────────
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

ENV VIRTUAL_ENV=/opt/venv \
    DOCLING_ARTIFACTS_PATH=/home/node/.cache/docling/models

RUN uv venv $VIRTUAL_ENV --python /usr/bin/python3 \
    && uv pip install --no-cache \
        --torch-backend=cpu \
        "docling-slim[standard]"

# ── XDG-compliant home structure for the node user ──────────────────────────
RUN mkdir -p \
    /workspace \
    /home/node/.npm-global \
    /home/node/.local/share/opencode \
    /home/node/.local/state \
    /home/node/.local/bin \
    /home/node/.cache/opencode \
    /home/node/.cache/docling/models \
    /home/node/.config \
    /home/node/.opencode-secrets \
    && chown -R node:node /workspace /home/node

# ── konrad-baked content (root-owned by design — node user can't tamper) ────
COPY konrad-defaults/  /etc/konrad/
COPY merge-config.js   /etc/konrad/merge-config.js
COPY entrypoint.sh     /usr/local/bin/konrad-entrypoint

ENV NODE_OPTIONS=--max-old-space-size=4096 \
    NPM_CONFIG_PREFIX=/home/node/.npm-global \
    PATH="/opt/venv/bin:/home/node/.npm-global/bin:/home/node/.local/bin:$PATH" \
    NODE_PATH=/usr/local/lib/node_modules

WORKDIR /workspace

# Node best-practices §6: drop privileges before installing user-space tooling
# and before runtime. konrad never runs anything as root post-build.
USER node

# Pre-download Docling models into the same cache path used at runtime.
RUN /opt/venv/bin/docling-tools models download

# Update npm to latest in the user prefix (silences the "new version of
# npm available!" notice during build, and keeps npm itself flowing
# through `konrad rebuild` like every other package). Then install
# opencode + the model-discovery plugin we declare in
# opencode-defaults.jsonc. Installing all of this at build time means
# the konrad-npm-global named volume gets seeded from this layer on
# first creation — opencode doesn't have to pull anything from npm at
# startup. Updates flow through `konrad rebuild`.
RUN npm install -g npm opencode-ai \
    && npm cache clean --force 

# Opencode-discoverable content (currently just the konrad primary agent;
# skills directory was removed pending a ground-up rebuild — see ROADMAP).
COPY --chown=node:node opencode/ /home/node/.config/opencode/

# Entrypoint runs the config merge + user-content layering before exec'ing
# the real command (opencode by default, see bin/konrad on the host).
ENTRYPOINT ["/usr/local/bin/konrad-entrypoint"]
