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
#   ripgrep, fd-find,
#   bat                 → match runtime image; opencode also prefers them
#
# Claude Code itself is delivered as the VS Code extension installed
# via devcontainer.json's customizations.vscode.extensions — no npm
# CLI needed.
RUN apt-get update && apt-get install -y --no-install-recommends \
        shellcheck \
        git curl jq ca-certificates sudo \
        ripgrep fd-find bat \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /var/log/apt/* /var/log/dpkg.log

# Debian renames fd → fdfind and bat → batcat; symlink to the canonical
# names the agent and image/Dockerfile both expect.
RUN ln -sf /usr/bin/fdfind /usr/local/bin/fd \
    && ln -sf /usr/bin/batcat /usr/local/bin/bat

# node user (UID 1000) already exists in node:26-trixie-slim.
# devcontainer.json's `updateRemoteUserUID` syncs it to the host UID
# at first start, so bind-mounted files have correct ownership.
USER node
WORKDIR /workspace
