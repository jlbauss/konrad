# Roadmap & Backlog

## Implemented

- [x] **Custom opencode agent profiles.** Use opencode's `agents/` mechanism to ship a customized Konrad prompt instead of the default build and plan agents.
- [x] **Other providers.** Remove hard-coded lm-studio as provider.
- [x] **Improve image.** Optimize structure and size. Follow Node best practices: https://github.com/nodejs/docker-node/blob/main/docs/BestPractices.md Include more relevant tools.
- [x] **Make image provider-agnostic.** Currently only lm studio is supported and the model is hardwired. Make it configurable, also from the tui.
- [x] **User config directory at `~/.config/konrad/`.** A standard home-dir location where users keep their own konrad settings — preferred model, UI language, default agent mode, whatever else accumulates. `bin/konrad` reads it on startup; bind-mount the relevant pieces (or pass them as env vars) into the container. Subsumes the "end-user config override" item below as the canonical place those overrides live.

## ToDo

- [ ] **Build a proper PDF skill.** Dont think from the tooling - current docling skill - but rather from the file type.
- [ ] **Publish on gitlab container registry.** implement an automated ci/cd workflow each time the containerfile is edited and daily or so.
- [ ] **Preconfigured MCP servers.** Bake in a couple of MCP servers (fs, fetch, gh) in `opencode.jsonc` so the model has working tools the moment it boots.
- [ ] **Fonts as a separate asset.** `frontend-dev/canvas-fonts/` is ~5.7M of TTFs in git. Move to LFS, a release tarball, or a download-on-first-use step.
- [ ] Potential additonal skills
  - [ ] Email (e.g. .eml files)
  - [ ] Markdown
  - [ ] html presentations?
  - [ ] 
- [ ] **frictionless install.** A `curl … | sh` one-liner (or a Homebrew tap) that drops `konrad` on `PATH` and pulls the image, so users don't need to clone the repo.
- [ ] **End-user config addition/override.** Let users append or override parts of the `opencode.jsonc` (model, provider, API keys) without rebuilding the image
- [ ] **Firewall.** Set up a very simple firewall that blocks all but allow-listed domains by default
- [ ] **opencode permission ACLs.** Use the `permission` block in `opencode.jsonc` to constrain which shell commands and tools the model can invoke without user confirmation.
- [ ] **Evaluate version pinning.** Right now we use auto-update: true which might lead to problems. We need to evaluate the best practices for how to handle this.
- [ ] **Docker support.** Currently Podman-only because of `--userns=keep-id`. A small Docker-compatible alternative `devcontainer.json` (or a conditional `runArgs`) would broaden the audience.
- [ ] **Multi-language support.** Today `AGENTS.md` and the bundled skill descriptions are English-only. Ship localized variants (German first) — likely as `AGENTS.<lang>.md` files plus a setting in `~/.config/konrad/` to pick the active language, so a non-English user gets the agent talking back in their language without prompting for it every time.
- [ ] **Top-level CI.** JSON/JSONC schema validation for the opencode configs, `shellcheck` on the bundled `.sh` files, and a "image actually builds" smoke job.
- [ ] **Specialized modes.** Add purpose-built modes — e.g. `konrad-default`, `konrad-perfectionist`.
- [ ] **Restore LM Studio dynamic model discovery.** The [`opencode-models-discovery`](https://github.com/rivy-t/opencode-models-discovery) plugin currently emits `modalities.output: ["embedding"]` for LM Studio embedding models, which opencode's config schema rejects (only `text|audio|image|video|pdf` allowed). LM Studio is excluded from the plugin's discovery as a workaround (`providers.exclude: ["lmstudio"]` in `opencode-defaults.jsonc`); the documented default model is hard-declared. File an upstream issue, drop the exclusion when fixed.
- [ ] **Replace `opencode-models-discovery` with inline discovery (startup perf).** Empirically the biggest single startup cost on konrad today: Bun spends ~3.7 s loading this external plugin from `~/.npm-global` before it does any useful work (confirmed by `konrad logs` — look for the `+3668ms loading plugin opencode-models-discovery` line). The plugin's own logic is small: probe each OpenAI-compatible provider's `/v1/models`, write the result into the config. Doing the same thing in `bin/konrad` (host-side curl) + `image/entrypoint.sh` (jq into the runtime override) is ~30 lines of bash and eliminates the plugin entirely. Trade-off: we maintain ~30 lines vs. a third-party plugin. Worth doing once the LM Studio embedding-modality issue above is also resolved (or doing both at once and dropping the plugin for good).
