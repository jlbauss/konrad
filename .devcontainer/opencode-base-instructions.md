# OpenCode Sandbox Base Instructions

Every project using this devcontainer inherits these facts automatically.

## Environment

- Devcontainer based on `node:24`
- Remote user is `node`, workspace at `/workspace`
- `NODE_OPTIONS=--max-old-space-size=4096` is set to avoid npm OOM on heavy installs
- Global npm prefix is `/home/node/.npm-global` (already on `PATH`) — needed because `/usr/local/lib/node_modules` is root-owned
- `opencode-ai` is installed globally inside the container

## Git workflow

- Perform a meaningful git commit whenever a new feature is implemented successfully.
