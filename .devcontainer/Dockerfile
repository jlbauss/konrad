# Start from the official Node.js 20 image.
# This gives us Node.js + npm pre-installed, which OpenCode needs to run.
FROM node:20

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

# Switch from root to the "node" user for safety.
# Everything after this runs as an unprivileged user.
USER node

# Install OpenCode globally so you can run it with just `opencode` in the terminal.
RUN npm install -g opencode-ai
