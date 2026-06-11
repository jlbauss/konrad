# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later

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
#        - models  (locks/models.lock: docling model repos tracked at main,
#                   pinned by commit; fetched by image/fetch-models.py so the
#                   model layer is byte-stable. Tableformer + rapidocr ride
#                   docling's own pins, not this lock.)
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
# When you add or remove a pin, update both this block *and* the
# ARCHITECTURE.md "Build & reproducibility" list so the two stay in sync.
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
# Downloads the Docling model set into /opt/models at *pinned* revisions, so
# the layer is byte-stable across rebuilds. image/fetch-models.py reuses
# docling's own per-model download logic (no re-implementing rapidocr's URL
# matrix) and injects the pinned shas from locks/models.lock for the repos
# docling otherwise resolves at a floating `main`. The post-download strip of
# .cache/.locks removes the only per-run-varying metadata; together with the
# CI rewrite-timestamp pass that makes the tree byte-identical run-to-run, so
# users skip the ~1.1 GB re-pull when the models didn't actually change.
# No repo files beyond the lock + fetcher. Invalidated only when Stage 1 or
# those two inputs change.
# =============================================================================
FROM python-base AS python-models

COPY locks/models.lock /tmp/models.lock
COPY fetch-models.py /tmp/fetch-models.py
# --mount=type=secret,id=hf_token (optional): when the build provides a
# HuggingFace token, huggingface_hub reads it from HF_TOKEN to lift the
# anonymous API rate limit — an unauthenticated download failed a build once.
# The guard leaves local builds (no secret) working, just rate-limited.
RUN --mount=type=secret,id=hf_token \
    mkdir -p /opt/models \
    && HF_TOKEN="$([ -f /run/secrets/hf_token ] && cat /run/secrets/hf_token || true)" \
       /opt/venv/bin/python /tmp/fetch-models.py /tmp/models.lock \
    && find /opt/models -type d \( -name .cache -o -name .locks \) -prune -exec rm -rf {} + \
    && rm /tmp/models.lock /tmp/fetch-models.py

# =============================================================================
# Stage 2b — venv-split
# Partitions the installed venv into three physical sets so the final image
# lays them down as separate layers (see the COPY trio in the final stage and
# ROADMAP "venv pull-dedupe"). Purely a delivery optimization: nothing runs
# here, and the sets recombine into one site-packages at the same paths, so
# Python neither knows nor cares which layer a package shipped in.
#
#   heavy → torch (+torchgen/functorch, dist-info): ~700 MB, the biggest blob,
#           and slow-moving (~6 releases/yr). Isolated so the frequent small-dep
#           bumps that don't touch torch dedupe its 700 MB on pull.
#   mid   → the large numeric wheels that each move only a few times a year
#           (opencv, scipy, numpy, onnxruntime, sympy): ~440 MB. One bucket —
#           fine-grained per-package layers would buy little for the churn.
#   light → everything LEFT in /opt/venv after the moves: the daily-churning
#           small pure-python deps + transformers (the most frequent mover) +
#           torchvision (tiny, rides torch's cadence). Re-pulls on most bumps.
#
# Empirical sizing + release-cadence rationale: ROADMAP.md. Keep heavy/mid lean
# — putting a churny package in a lower layer forfeits its dedup. uv does not
# compile bytecode by default, so there are no __pycache__/.pyc to destabilise
# the layers; the CI rewrite-timestamp pass normalises mtimes. A separate stage
# (not python-base) so python-models above keeps the whole venv it builds on.
# =============================================================================
FROM python-base AS venv-split

# cd into the glob-resolved site-packages; WORKDIR can't take a wildcard, and
# this throwaway stage runs nothing afterwards.
# hadolint ignore=DL3003
RUN set -eux; \
    SP="$(echo /opt/venv/lib/python3.*/site-packages)"; \
    [ -d "$SP" ] || { echo "site-packages not found at $SP" >&2; exit 1; }; \
    mkdir -p /opt/venv-heavy /opt/venv-mid; \
    cd "$SP"; \
    for d in torch torchgen functorch torch-*.dist-info; do \
      if [ -e "$d" ]; then mv "$d" /opt/venv-heavy/; fi; \
    done; \
    for d in cv2 opencv_python.libs opencv_python-*.dist-info \
             scipy scipy.libs scipy-*.dist-info \
             numpy numpy.libs numpy-*.dist-info \
             onnxruntime onnxruntime-*.dist-info \
             sympy sympy-*.dist-info; do \
      if [ -e "$d" ]; then mv "$d" /opt/venv-mid/; fi; \
    done; \
    test -d /opt/venv-heavy/torch

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
#   tinyproxy                   → egress firewall: runs as the sidecar proxy that
#                                 enforces the default-deny allow-list (the agent
#                                 container reaches the network only through it).
#                                 Same image doubles as the proxy — one pinned
#                                 artifact, no second image to pull. See
#                                 konrad-proxy-entrypoint.sh and bin/konrad.
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
    ripgrep fd-find bat tree gh tinyproxy \
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
# see REUSE.toml for the consolidated list.
# --chmod=0755: see the konrad-entrypoint COPY below — fontconfig runs as the
# non-root node user and must be able to traverse these dirs and read the .ttf
# files, so we can't rely on the build context preserving their mode.
COPY --chmod=0755 fonts/konrad/ /usr/local/share/fonts/konrad/
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
# and absolute references inside the venv remain valid. uv comes along too —
# needed at runtime for `uv pip list` in the build manifest script and useful
# for `uv pip install` extensions.
#
# The venv arrives as THREE layers (see the venv-split stage) so a routine
# python.lock bump — which moves a small pure-python dep almost daily — re-pulls
# only the light remainder, while torch (~700 MB) and the mid-stable numeric set
# (~440 MB) dedupe. The three COPYs reconstruct one site-packages at the venv's
# real paths; stable-first ordering (torch, then mid, then light) keeps the
# rarest-changing bytes in the lowest layers. PYTHON_TAG must match the venv's
# python minor (asserted in venv-split via the lib/python3.* glob); bump it in
# lockstep when the base image's python moves — a mismatch lands torch at the
# wrong site-packages path and the smoke test catches it.
ARG PYTHON_TAG=python3.13
COPY --from=venv-split  /opt/venv-heavy/  /opt/venv/lib/${PYTHON_TAG}/site-packages/
COPY --from=venv-split  /opt/venv-mid/    /opt/venv/lib/${PYTHON_TAG}/site-packages/
COPY --from=venv-split  /opt/venv         /opt/venv
COPY --from=python-base               /usr/local/bin/uv  /usr/local/bin/uv

# Docling models: baked root-owned at /opt/models (outside $HOME) and read-only
# at runtime — docling resolves them via DOCLING_ARTIFACTS_PATH. One COPY per
# model so each is its *own* layer: a single-model update re-pulls only that
# model, not the whole ~1.1 GB set. Keeping them out of /home/node is also what
# lets the home-scaffolding block below own the node home with a cheap
# recursive chown (no 1.1 GB copy-up). The folder names are docling's
# convention (repo_id '/' -> '--', plus the literal "RapidOcr").
COPY --from=python-models /opt/models/docling-project--docling-layout-heron            /opt/models/docling-project--docling-layout-heron
COPY --from=python-models /opt/models/docling-project--docling-models                  /opt/models/docling-project--docling-models
COPY --from=python-models /opt/models/docling-project--CodeFormulaV2                   /opt/models/docling-project--CodeFormulaV2
COPY --from=python-models /opt/models/docling-project--DocumentFigureClassifier-v2.5   /opt/models/docling-project--DocumentFigureClassifier-v2.5
COPY --from=python-models /opt/models/RapidOcr                                         /opt/models/RapidOcr

ENV VIRTUAL_ENV=/opt/venv \
    DOCLING_ARTIFACTS_PATH=/opt/models

# ── XDG home structure for the node user — node owns its whole home ──────────
# With the Docling model cache now baked at /opt/models (outside $HOME), the
# heavy content that used to make `chown -R /home/node` prohibitively expensive
# (overlayfs copies every file up on a metadata change) is gone — so node owns
# its home outright. That lets the runtime user create dirs anywhere under
# $HOME (e.g. the font overlay's ~/.local/share/fonts) without the old dance of
# naming every intermediate parent so `install -d` wouldn't leave a root-owned
# gap beneath an auto-created one. mkdir -p seeds the dirs that must exist as
# mount points / runtime targets; the recursive chown is cheap here because the
# npm + opencode content lands in later layers. (npm installs opencode as root
# into .npm-global below — node can't write there, nor needs to.)
RUN mkdir -p \
    /workspace \
    /home/node/.npm-global \
    /home/node/.local/share/opencode \
    /home/node/.local/share/fonts \
    /home/node/.local/state \
    /home/node/.local/bin \
    /home/node/.cache/opencode \
    /home/node/.config \
    /home/node/.opencode-secrets \
    && chown -R node:node /home/node /workspace

# ── Konrad system files (root-owned — node user can't tamper) ───────────────
# Ordered rarest-to-change first so that editing these files invalidates as
# few downstream layers as possible. environment.md is NOT here — it lives
# in opencode/ below so edits to it never touch the npm layer.
# --chmod=0755, NOT 0644: this COPY is what creates /etc/konrad, and BuildKit
# applies a COPY's --chmod to the parent dirs it auto-creates. A 0644 here
# makes /etc/konrad itself non-traversable (no +x) for the non-root `node`
# runtime user, hiding every file under it — the entrypoint can't read
# opencode-defaults.jsonc and `test -f /etc/konrad/build-manifest.json` fails
# in smoke. buildah (local podman builds) does NOT propagate --chmod to created
# parents, so this only surfaces in CI's BuildKit build. 0755 is harmless for a
# node-run script (still world-readable; the +x bit is unused). Keep it 0755.
COPY --chmod=0755 merge-config.js /etc/konrad/merge-config.js
# --chmod=0755 is load-bearing: this file is the ENTRYPOINT, so crun must be
# able to exec it. Plain COPY inherits the build-context mode, which is not
# preserved reliably when the context ships to a remote builder (e.g. the
# podman-machine VM on macOS) — a dropped +x bit there bakes a non-executable
# entrypoint and the container dies with "is not executable: OCI permission
# denied". Setting the mode explicitly removes that dependency entirely.
COPY --chmod=0755 entrypoint.sh /usr/local/bin/konrad-entrypoint
# The egress-firewall sidecar runs THIS image with konrad-proxy as its command:
# it composes the same baked<org<user config, derives the allow-list from the
# merged provider endpoints + a baked infra floor + the user's allowed_hosts,
# writes a tinyproxy default-deny config, and execs tinyproxy. Root-owned (0755)
# so the node runtime user can't tamper with the allow-list logic. See bin/konrad.
COPY --chmod=0755 konrad-proxy-entrypoint.sh /usr/local/bin/konrad-proxy
COPY --chmod=0755 konrad-defaults/ /etc/konrad/

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
