# Roadmap & Backlog

## Implemented

- [x] **Custom opencode agent profiles.** Use opencode's `agents/` mechanism to ship a customized Konrad prompt instead of the default build and plan agents.

## ToDo

- [ ] **Other providers.** Remove hard-coded lm-studio as provider.
- [ ] **publish image in container registry.** implement an automated ci/cd workflow each time the containerfile is edited and daily or so.
- [ ] **bug: Agent does not do the file-based workflow and does not use todowrite.** find out why and how to solve it.
- [ ] **Preconfigured MCP servers.** Bake in a couple of MCP servers (fs, fetch, gh) in `opencode.jsonc` so the model has working tools the moment it boots.
- [ ] **Skill Refactoring.** Currently, we blindly imported the minimax skills. They might be overly complex or unfunctional. Sample tasks:
  - [ ] **Deduplicate MiniMax scripts.** `frontend-dev/scripts/minimax_image.py` and `gif-sticker-maker/scripts/minimax_image.py` (plus `_video.py`) have already drifted. Extract a shared `lib/minimax/` or canonicalize one copy.
  - [ ] **Lint SKILL.md frontmatter.** Tiny CI script: validate `name`/`description`/`license` exist, validate referenced `scripts/*` paths resolve.
  - [ ] **Trim multilingual triggers and description bloat.** `minimax-docx`'s frontmatter alone runs ~30 lines. For a 30B-class local model, every byte of description competes with task context.
  - [ ] **Normalize skill layout.** `minimax-docx`'s own `setup.sh` re-installs .NET which the Dockerfile already provides — pick a canonical skill shape and drop redundant per-skill bootstrap.
  - [ ] **Fonts as a separate asset.** `frontend-dev/canvas-fonts/` is ~5.7M of TTFs in git. Move to LFS, a release tarball, or a download-on-first-use step.
- [ ] **Make image provider-agnostic.** Currently only lm studio is supported and the model is hardwired. Make it configurable, also from the tui.
- [ ] **frictionless install.** A `curl … | sh` one-liner (or a Homebrew tap) that drops `konrad` on `PATH` and pulls the image, so users don't need to clone the repo.
- [ ] **End-user config addition/override.** Let users append or override parts of the `opencode.jsonc` (model, provider, API keys) without rebuilding the image
- [ ] **Firewall.** Set up a very simple firewall that blocks all but allow-listed domains by default
- [ ] **opencode permission ACLs.** Use the `permission` block in `opencode.jsonc` to constrain which shell commands and tools the model can invoke without user confirmation.
- [ ] **User config directory at `~/.config/konrad/`.** A standard home-dir location where users keep their own konrad settings — preferred model, UI language, default agent mode, whatever else accumulates. `bin/konrad` reads it on startup; bind-mount the relevant pieces (or pass them as env vars) into the container. Subsumes the "end-user config override" item below as the canonical place those overrides live.
- [ ] **Evaluate version pinning.** Right now we use auto-update: true which might lead to problems. We need to evaluate the best practices for how to handle this.
- [ ] **Docker support.** Currently Podman-only because of `--userns=keep-id`. A small Docker-compatible alternative `devcontainer.json` (or a conditional `runArgs`) would broaden the audience.
- [ ] **Multi-language support.** Today `AGENTS.md` and the bundled skill descriptions are English-only. Ship localized variants (German first) — likely as `AGENTS.<lang>.md` files plus a setting in `~/.config/konrad/` to pick the active language, so a non-English user gets the agent talking back in their language without prompting for it every time.
- [ ] **Top-level CI.** JSON/JSONC schema validation for the opencode configs, `shellcheck` on the bundled `.sh` files, and a "image actually builds" smoke job.
- [ ] **Specialized modes.** Add purpose-built modes — e.g. `konrad-default`, `konrad-perfectionist`.