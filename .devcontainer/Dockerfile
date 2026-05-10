# Start from the official Node.js 24 image (oldstable in 2026).
# This gives us Node.js + npm pre-installed, which OpenCode needs to run.
FROM node:24

# Install a few essential system packages.
# --no-install-recommends keeps the image small by skipping suggested packages.
# apt-get clean && rm ... removes the package cache to save disk space.
RUN apt-get update && apt-get install -y --no-install-recommends \
  git \
  sudo \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Create the /workspace directory where your project files will live,
# and make the "node" user the owner (so you can edit files without being root).
RUN mkdir -p /workspace && chown -R node:node /workspace

# Set the default directory when you open a terminal in the container.
WORKDIR /workspace

# Increase Node.js memory limit so npm doesn't crash during heavy installs.
ENV NODE_OPTIONS=--max-old-space-size=4096

# Set up a global npm directory that the "node" user can write to.
# Without this, "npm install -g" fails because the default location
# (/usr/local/lib/node_modules) is owned by root.
ENV NPM_CONFIG_PREFIX=/home/node/.npm-global
ENV PATH=$PATH:/home/node/.npm-global/bin

# Switch from root to the "node" user for safety.
# Everything after this runs as an unprivileged user.
USER node

# Install OpenCode globally so you can run it with just `opencode` in the terminal.
# The -g flag makes it available as a system-wide command.
RUN npm install -g opencode-ai
