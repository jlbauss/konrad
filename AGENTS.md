# AGENTS.md

## Project type

This repo is where the sandboxed devcontainer for OpenCode is developed. There is no build, test, or lint pipeline.

## Environment

- Devcontainer based on `node:24` (Dockerfile in `.devcontainer/`)
- Remote user is `node`, workspace at `/workspace`
- `NODE_OPTIONS=--max-old-space-size=4096` is set to avoid npm OOM on heavy installs
- Global npm prefix is `/home/node/.npm-global` (already on `PATH`) — needed because `/usr/local/lib/node_modules` is root-owned
- `opencode-ai` is installed globally inside the container

## Git workflow

- Perform a meaningful git commit whenever a new feature is implemented successfully.

## OpenCode config

- Provider: OpenRouter (config in `opencode.json`)
- API key is set via `/connect` inside OpenCode, not in config files
