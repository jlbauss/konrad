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
    git gh curl jq ca-certificates sudo \
    openssh-client \
    ripgrep fd-find bat \
    trash-cli libglib2.0-bin \
    unzip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /var/log/apt/* /var/log/dpkg.log

# uv: pulled from Astral's official image. uv manages its own Python
# toolchains, so no system Python install needed alongside.
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

# Debian renames fd → fdfind and bat → batcat; symlink to the canonical
# names the agent and image/Dockerfile both expect.
RUN ln -sf /usr/bin/fdfind /usr/local/bin/fd \
    && ln -sf /usr/bin/batcat /usr/local/bin/bat

# Wrapper around /usr/bin/gio that routes `gio trash` through trash-cli.
# See gio-shim itself for the why (GIO refuses bind mounts, breaking
# VS Code's Move-to-Trash UI under /workspace). /usr/local/bin wins
# over /usr/bin in PATH so VS Code's gio invocations hit this first.
COPY --chmod=0755 gio-shim /usr/local/bin/gio

# Pre-create the dirs that devcontainer.json mounts named volumes onto,
# owned by node. Podman copies the image's directory state into an
# empty named volume on first mount, so this seeds the volume with the
# correct ownership — without it the volume would be root-owned and
# the node user could not write to it.
RUN install -d -o node -g node \
    /home/node/.claude \
    /home/node/.vscode-server

# node user (UID 1000) already exists in node:26-trixie-slim.
# devcontainer.json's runArgs --userns=keep-id maps it to the host
# user's UID/GID at namespace level, so bind-mounted files have
# correct ownership without further intervention.
USER node
WORKDIR /workspace
