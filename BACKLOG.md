# Backlog

Things we've deliberately deferred. Roughly grouped by theme.

## Sandbox / security

- **Egress firewall.** Install-time scripts that configure `iptables` + `ipset` to restrict outbound traffic to package registries, GitHub, and a small allowlist. Requires `--cap-add=NET_ADMIN` in `runArgs` and an init script invoked via `postStartCommand`. Until this lands, the `AGENTS.md` claim "firewall-restricted egress" should be considered aspirational.
- **opencode permission ACLs.** Use the `permission` block in `opencode.jsonc` to constrain which shell commands and tools the model can invoke without user confirmation.

## Configuration

- **API key passthrough.** Add `remoteEnv`/`containerEnv` in `devcontainer.json` for `MINIMAX_API_KEY`, `OPENROUTER_API_KEY`, etc. — currently only the keyless LM Studio flow is supported.
- **Pin opencode version, disable autoupdate.** `autoupdate: true` makes the immutable-image story fuzzy and silently changes behavior. Pin via the `npm install -g opencode-ai@<version>` line in the Dockerfile and set `autoupdate: false`.
- **Docker support.** Currently Podman-only because of `--userns=keep-id`. A small Docker-compatible alternative `devcontainer.json` (or a conditional `runArgs`) would broaden the audience.

## Agent capabilities

- **Preconfigured MCP servers.** Bake in a couple of MCP servers (fs, fetch, gh) in `opencode.jsonc` so the model has working tools the moment it boots.
- **Custom opencode agent profiles.** Use opencode's `agents/` mechanism to ship purpose-built modes — e.g. `research`, `code-only`, `no-network`.

## Skills hygiene

- **Deduplicate MiniMax scripts.** `frontend-dev/scripts/minimax_image.py` and `gif-sticker-maker/scripts/minimax_image.py` (plus `_video.py`) have already drifted. Extract a shared `lib/minimax/` or canonicalize one copy.
- **Lint SKILL.md frontmatter.** Tiny CI script: validate `name`/`description`/`license` exist, validate referenced `scripts/*` paths resolve.
- **Trim multilingual triggers and description bloat.** `minimax-docx`'s frontmatter alone runs ~30 lines. For a 30B-class local model, every byte of description competes with task context.
- **Normalize skill layout.** `minimax-docx`'s own `setup.sh` re-installs .NET which the Dockerfile already provides — pick a canonical skill shape and drop redundant per-skill bootstrap.
- **Fonts as a separate asset.** `frontend-dev/canvas-fonts/` is ~5.7M of TTFs in git. Move to LFS, a release tarball, or a download-on-first-use step.

## DX

- **Top-level CI.** JSON/JSONC schema validation for the opencode configs, `shellcheck` on the bundled `.sh` files, and a "image actually builds" smoke job.
- **`.editorconfig` + `.gitattributes`.** Especially for the cross-platform shell/powershell scripts inside skills.
