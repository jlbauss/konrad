# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Claude dev container — for working ON konrad.
#
# Distinct from devcontainer/ (no dot, at repo root), which is the
# dormant "Konrad-as-devcontainer" consumption path (see ROADMAP.md,
# Future features).
#
# Same base as konrad's own runtime image (image/Dockerfile) so the
# dev environment matches what ships to users.
FROM node:26-trixie-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# Tools needed to work on konrad. shellcheck and bash -n are the
# project's validation loop (no test suite — see CLAUDE.md). The rest
# is parity with the runtime image so file paths / grep results match
# what the agent will see at runtime.
#
#   shellcheck          → lints bin/konrad, entrypoint, scripts/*.sh
#   yamllint            → YAML syntax + style across .github/workflows/
#                         and devcontainer.json. Sharper than `python3 -c
#                         "import yaml"` for the everyday "did I write
#                         valid YAML" check.
#   git, jq, curl, sudo → daily-use
#   openssh-client      → `ssh` binary so `git push` over SSH remotes
#                         works. VS Code forwards the host's SSH agent
#                         via SSH_AUTH_SOCK, so no key management
#                         needed inside the container — the host agent
#                         serves keys transparently.
#   ripgrep, fd-find,
#   bat                 → match runtime image; opencode also prefers them
#   trash-cli           → `trash` / `trash-list` / `trash-restore` etc.
#                         so terminal deletes are recoverable.
#   libglib2.0-bin      → provides `gio`, which VS Code uses to move
#                         files to Trash from the file explorer on Linux.
#   unzip               → scripts/fetch-fonts.sh extracts upstream font
#                         release zips (Inter, JetBrains Mono).
#   podman              → client only. Talks to the HOST's rootless podman
#                         socket (mounted by devcontainer.json, addressed via
#                         CONTAINER_HOST) so the agent can exercise the konrad
#                         runtime image from in here — `konrad-dev --rebuild`,
#                         `./scripts/smoke-test.sh konrad:local`, shelling into
#                         the image. Daemonless: nothing runs locally, it's a
#                         pure remote client. See CLAUDE.md "Self-testing".
#
# Plus `uv` (installed via the COPY below, not apt) for spinning up
# matching Python deps when verifying skill helpers and recipes against
# the libraries that ship in konrad's runtime /opt/venv (pdfplumber,
# pypdf, reportlab). Skill code itself runs in konrad's image, not here
# — this is just so we can sanity-check API assumptions locally without
# needing the full konrad image.
#
# Claude Code itself is delivered as the VS Code extension installed
# via devcontainer.json's customizations.vscode.extensions — no npm
# CLI needed.
RUN apt-get update && apt-get install -y --no-install-recommends \
    shellcheck \
    yamllint \
    git gh curl jq ca-certificates sudo \
    openssh-client \
    ripgrep fd-find bat \
    trash-cli libglib2.0-bin \
    unzip \
    podman \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /var/log/apt/* /var/log/dpkg.log

# uv: pulled from Astral's official image. uv manages its own Python
# toolchains, so no system Python install needed alongside.
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

# Standalone validators not in apt — Go and Haskell binaries from the
# upstreams' GitHub releases. Pinned by version so dev-container builds
# are reproducible; bump deliberately when there's a reason.
#
#   actionlint → GitHub Actions workflow validation. Sharper than yamllint
#                for .github/workflows/*.yml because it understands the
#                Actions semantics (invalid step refs, expression typos,
#                shell injection in `run:`). https://github.com/rhysd/actionlint
#   hadolint   → Dockerfile linter. Catches apt cache cleanup misses,
#                COPY ownership smells, layer-ordering issues that
#                shellcheck and bash -n can't see. https://github.com/hadolint/hadolint
#
# Both pinned for dev-container reproducibility. Bump when bumping
# matters (e.g. new rule we want, or an upstream fix).
ARG ACTIONLINT_VERSION=1.7.12
ARG HADOLINT_VERSION=2.14.0

COPY --from=docker.io/hadolint/hadolint:v${HADOLINT_VERSION} /bin/hadolint /usr/local/bin/hadolint
RUN hadolint --version


COPY --from=docker.io/rhysd/actionlint:${ACTIONLINT_VERSION} /usr/local/bin/actionlint /usr/local/bin/actionlint
RUN actionlint -version


# Dev venv at /opt/dev-venv — pre-installed Python validators on PATH so
# one-shot "import yaml" / "check-jsonschema foo.json" calls Just Work
# without re-creating an ephemeral venv each time. Distinct from konrad's
# runtime /opt/venv (which holds docling, reportlab, etc.) — this venv
# is just dev-container tooling.
#
#   pyyaml           → `python3 -c "import yaml; ..."` for ad-hoc YAML
#                      parsing / round-trip checks that yamllint doesn't
#                      cover.
#   check-jsonschema → opencode.jsonc validation against opencode's
#                      schema, JSON files against committed schemas, etc.
#   reuse            → REUSE/SPDX licensing check (`reuse lint`) — the repo's
#                      licensing convention (see CONTRIBUTING / CLAUDE.md), so
#                      it can be run locally without an ephemeral install.
RUN uv venv /opt/dev-venv --python-preference=managed --python=3.13 \
    && uv pip install --python /opt/dev-venv/bin/python --no-cache \
         pyyaml check-jsonschema 'reuse[charset-normalizer]'

ENV PATH="/opt/dev-venv/bin:$PATH"

# Debian renames fd → fdfind and bat → batcat; symlink to the canonical
# names the agent and image/Dockerfile both expect.
RUN ln -sf /usr/bin/fdfind /usr/local/bin/fd \
    && ln -sf /usr/bin/batcat /usr/local/bin/bat

# konrad-dev → the checkout's CLI, preprovisioned for self-testing. bin/konrad
# picks its default image from its own basename (invoked as `konrad-dev` ⇒
# defaults to konrad:local), so the symlink NAME is the whole mechanism —
# `konrad-dev --rebuild` / `konrad-dev --shell` then work the moment the
# container is up, no manual setup. /usr/local/bin is already on PATH, so no
# ~/.local/bin dance (that recipe is for a native checkout — see CONTRIBUTING).
# Target resolves at runtime via the /workspace bind mount; a dangling symlink
# at build time is fine.
RUN ln -sf /workspace/bin/konrad /usr/local/bin/konrad-dev

# Wrapper around /usr/bin/gio that routes `gio trash` through trash-cli.
# See gio-shim itself for the why (GIO refuses bind mounts, breaking
# VS Code's Move-to-Trash UI under /workspace). /usr/local/bin wins
# over /usr/bin in PATH so VS Code's gio invocations hit this first.
COPY --chmod=0755 gio-shim /usr/local/bin/gio

# Pre-create the parent dirs that devcontainer.json mounts onto, owned by node.
# For the named-volume mounts (.claude, .vscode-server) podman seeds the empty
# volume from the image's directory state, so this gives the volume node
# ownership instead of root. For the ~/.config/konrad BIND mount, pre-creating
# ~/.config (and the konrad mountpoint) stops podman from creating ~/.config
# itself as root when it makes the mountpoint — a root-owned ~/.config breaks
# the podman client (it can't write ~/.config/containers) and `podman machine`.
# Without these the node user could not write the mount parents.
RUN install -d -o node -g node \
    /home/node/.claude \
    /home/node/.vscode-server \
    /home/node/.config \
    /home/node/.config/konrad

# node user (UID 1000) already exists in node:26-trixie-slim.
# devcontainer.json's runArgs --userns=keep-id maps it to the host
# user's UID/GID at namespace level, so bind-mounted files have
# correct ownership without further intervention.
USER node
WORKDIR /workspace
