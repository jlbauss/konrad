# AGENTS.md

## Project type

This repo is where the sandboxed devcontainer for OpenCode is developed. There is no build, test, or lint pipeline.

## Shared instructions

Container-level facts (environment, git workflow) are baked into the Docker image at `/home/node/.opencode-base-instructions.md` and referenced via `opencode.json` `instructions`. Every project using this devcontainer inherits them automatically.

When updating container-level guidance, edit `.devcontainer/opencode-base-instructions.md` — not individual project `AGENTS.md` files.

## OpenCode config

- Provider: OpenRouter (config in `opencode.json`)
- API key is set via `/connect` inside OpenCode, not in config files
