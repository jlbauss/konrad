FROM node:24

LABEL org.opencontainers.image.title="konrad" \
      org.opencontainers.image.description="Sandboxed opencode for local agent models, preloaded with skills and instructions." \
      org.opencontainers.image.licenses="GPL-3.0-only" \
      org.opencontainers.image.source="https://github.com/jan-luca-bauss/konrad"

ENV DEBIAN_FRONTEND=noninteractive

# System packages: tools the agent actually uses + comfort tools for
# interactive shells (zsh, nano, htop, man-db). Apt cleanup happens in
# the same RUN so the cache layer stays small.
RUN apt-get update && apt-get install -y --no-install-recommends \
    less git procps fzf zsh man-db unzip gnupg2 nano \
    gh iproute2 dnsutils jq \
    ripgrep fd-find bat tree htop \
    pandoc poppler-utils tesseract-ocr imagemagick ffmpeg \
    python3 curl ca-certificates \
    fonts-dejavu fonts-liberation fonts-noto-core \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# Debian renames fd → fdfind and bat → batcat; symlink to the canonical names.
RUN ln -sf /usr/bin/fdfind /usr/local/bin/fd && \
    ln -sf /usr/bin/batcat /usr/local/bin/bat

RUN mkdir -p /workspace && chown -R node:node /workspace
WORKDIR /workspace

# uv (Python toolchain manager)
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

# System-wide Python venv with libs the bundled skills depend on.
ENV VIRTUAL_ENV=/opt/venv
RUN uv venv $VIRTUAL_ENV --python /usr/bin/python3 && \
    uv pip install --no-cache \
      reportlab pypdf matplotlib \
      pandas openpyxl \
      "markitdown[pptx]"

# Node tools for minimax-pdf (playwright/chromium) and pptx-generator (pptxgenjs).
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/playwright-browsers
RUN npm install -g playwright pptxgenjs && \
    npx playwright install --with-deps chromium

# .NET SDK 8 for minimax-docx.
ENV DOTNET_ROOT=/usr/share/dotnet \
    DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_NOLOGO=1
RUN curl -sSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh && \
    chmod +x /tmp/dotnet-install.sh && \
    /tmp/dotnet-install.sh --channel 8.0 --install-dir "$DOTNET_ROOT" && \
    ln -s "$DOTNET_ROOT/dotnet" /usr/local/bin/dotnet && \
    rm /tmp/dotnet-install.sh

# Pre-create the node user's XDG dirs, npm prefix, and the secrets dir
# (for auth.json). Without this, Podman creates these as root when
# mounting volumes under them and opencode's runtime mkdirs hit EACCES.
RUN mkdir -p \
      /home/node/.npm-global \
      /home/node/.local/share/opencode \
      /home/node/.local/state \
      /home/node/.local/bin \
      /home/node/.cache/opencode \
      /home/node/.config \
      /home/node/.opencode-secrets \
  && chown -R node:node \
      /home/node/.npm-global \
      /home/node/.local \
      /home/node/.cache \
      /home/node/.config \
      /home/node/.opencode-secrets

ENV NODE_OPTIONS=--max-old-space-size=4096 \
    NPM_CONFIG_PREFIX=/home/node/.npm-global \
    PATH="/opt/venv/bin:/home/node/.npm-global/bin:/home/node/.local/bin:$PATH" \
    NODE_PATH=/usr/local/lib/node_modules

USER node

RUN npm install -g opencode-ai

COPY --chown=node:node opencode /home/node/.config/opencode/

# Entrypoint sets up the auth.json symlink before exec'ing the real command.
COPY --chown=node:node entrypoint.sh /usr/local/bin/konrad-entrypoint
ENTRYPOINT ["/usr/local/bin/konrad-entrypoint"]
