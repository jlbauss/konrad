FROM node:24

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
  less git procps fzf zsh man-db unzip gnupg2 nano \
  gh iptables ipset iproute2 dnsutils aggregate jq \
  ripgrep fd-find bat tree htop \
  pandoc poppler-utils tesseract-ocr imagemagick ffmpeg \
  python3 curl ca-certificates \
  && rm -rf /var/lib/apt/lists/*

RUN ln -sf /usr/bin/fdfind /usr/local/bin/fd && \
  ln -sf /usr/bin/batcat /usr/local/bin/bat

RUN mkdir -p /workspace && chown -R node:node /workspace
WORKDIR /workspace

# uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

# System-wide Python venv with libs for all four skills
ENV VIRTUAL_ENV=/opt/venv
RUN uv venv $VIRTUAL_ENV --python 3.12 && \
  uv pip install --no-cache \
  reportlab pypdf \
  pandas openpyxl \
  "markitdown[pptx]"

# Node tools for minimax-pdf (playwright/chromium) and pptx-generator (pptxgenjs)
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/playwright-browsers
RUN npm install -g playwright pptxgenjs && \
  npx playwright install --with-deps chromium && \
  rm -rf /var/lib/apt/lists/*

# .NET SDK 8 for minimax-docx
ENV DOTNET_ROOT=/usr/share/dotnet \
  DOTNET_CLI_TELEMETRY_OPTOUT=1 \
  DOTNET_NOLOGO=1
RUN curl -sSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh && \
  chmod +x /tmp/dotnet-install.sh && \
  /tmp/dotnet-install.sh --channel 8.0 --install-dir "$DOTNET_ROOT" && \
  ln -s "$DOTNET_ROOT/dotnet" /usr/local/bin/dotnet && \
  rm /tmp/dotnet-install.sh

# Node user's npm prefix
RUN mkdir -p /home/node/.npm-global && chown -R node:node /home/node/.npm-global

ENV NODE_OPTIONS=--max-old-space-size=4096 \
  NPM_CONFIG_PREFIX=/home/node/.npm-global \
  PATH="/opt/venv/bin:/home/node/.npm-global/bin:/home/node/.local/bin:$PATH"

USER node

RUN npm install -g opencode-ai && \
  uv tool install httpie

COPY --chown=node:node opencode /home/node/.config/opencode/