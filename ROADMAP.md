# Roadmap & Backlog

# Inbox

- [ ] do a real cleanup of everything. There are a lot of commentaries and prints that do not resemble the current truth. Remove model discovery for now. Make the roadmap pretty again.
- [ ] add to readme that vision enabled models should be used
- [ ] establish high-quality aspiration of Konrad. Konrad does not produce ai slop. Either he produces high quality outputs or he tells the user that he is not able to do. In this context: Add quality assurance workflow, e.g. utilizing a quality assurance subagent.
- [ ] improve build process so we always get the up-to-date packages for everything. Updates are important.
- [ ] outputs, such as csvs, must be in utf-8 format
- [ ] integrate planning-with-files with todowrite so the user is getting displayed the current todo list visibl
- [ ] remove requirement to have opencode session/working state in .agent
- [ ] i want Konrad to do an understanding-planning-task refinement roundtrip. He should make sure to understand what the user wants - even if the user does not really understand what they want in the first place
 
## ToDo

### needed before first beta shipping

- [ ] **Build a proper PDF skill.** Dont think from the tooling - current docling skill - but rather from the file type.
  - [ ] subtasks: extract, edit, generate, fill
- [ ] **build a proper spreadsheet (xlsx/ods/csv) skill**
- [ ] **Publish on gitlab container registry.** implement an automated ci/cd workflow each time the containerfile is edited and daily or so.
- [ ] **Preconfigured MCP servers.** Bake in a couple of MCP servers (fs, fetch, gh) in `opencode.jsonc` so the model has working tools the moment it boots.
- [ ] **Fonts as a separate asset.** `frontend-dev/canvas-fonts/` is ~5.7M of TTFs in git. Move to LFS, a release tarball, or a download-on-first-use step.
- [ ] **frictionless install.** A `curl … | sh` one-liner (or a Homebrew tap) that drops `konrad` on `PATH` and pulls the image, so users don't need to clone the repo.
- [ ] **Firewall.** Set up a very simple firewall that blocks all but allow-listed domains by default
- [ ] **Evaluate version pinning.** Right now we use auto-update: true which might lead to problems. We need to evaluate the best practices for how to handle this.
- [ ] **local models work flawlessly**
- [ ] **Security Audit**
- [ ] **update and streamline all documentation**

### future features

- [ ] **Multi-language support.** Today `AGENTS.md` and the bundled skill descriptions are English-only. Ship localized variants (German first) — likely as `AGENTS.<lang>.md` files plus a setting in `~/.config/konrad/` to pick the active language, so a non-English user gets the agent talking back in their language without prompting for it every time.
- [ ] **Potential additonal skills**
  - [ ] Email (e.g. .eml files)
  - [ ] Markdown
  - [ ] html presentations?
- [ ] **Docker support.** Currently Podman-only because of `--userns=keep-id`. A small Docker-compatible alternative `devcontainer.json` (or a conditional `runArgs`) would broaden the audience.
- [ ] **Top-level CI.** JSON/JSONC schema validation for the opencode configs, `shellcheck` on the bundled `.sh` files, and a "image actually builds" smoke job.
- [ ] **Replace `opencode-models-discovery` with inline discovery (startup perf).** Empirically the biggest single startup cost on konrad today: Bun spends ~3.7 s loading this external plugin from `~/.npm-global` before it does any useful work (confirmed by `konrad logs` — look for the `+3668ms loading plugin opencode-models-discovery` line). The plugin's own logic is small: probe each OpenAI-compatible provider's `/v1/models`, write the result into the config. Doing the same thing in `bin/konrad` (host-side curl) + `image/entrypoint.sh` (jq into the runtime override) is ~30 lines of bash and eliminates the plugin entirely. Trade-off: we maintain ~30 lines vs. a third-party plugin. Worth doing once the LM Studio embedding-modality issue above is also resolved (or doing both at once and dropping the plugin for good).

## Implemented

- [x] **Custom opencode agent profiles.** Use opencode's `agents/` mechanism to ship a customized Konrad prompt instead of the default build and plan agents.
- [x] **Other providers.** Remove hard-coded lm-studio as provider.
- [x] **Improve image.** Optimize structure and size. Follow Node best practices: https://github.com/nodejs/docker-node/blob/main/docs/BestPractices.md Include more relevant tools.
- [x] **Make image provider-agnostic.** Currently only lm studio is supported and the model is hardwired. Make it configurable, also from the tui.
- [x] **User config directory at `~/.config/konrad/`.** A standard home-dir location where users keep their own konrad settings — preferred model, UI language, default agent mode, whatever else accumulates. `bin/konrad` reads it on startup; bind-mount the relevant pieces (or pass them as env vars) into the container. Subsumes the "end-user config override" item below as the canonical place those overrides live.
- [x] **opencode permission ACLs.** Use the `permission` block in `opencode.jsonc` to constrain which shell commands and tools the model can invoke without user confirmation.

## Obsolete

- [ ] **Specialized modes.** Add purpose-built modes — e.g. `konrad-default`, `konrad-perfectionist`.
- [ ] **Restore LM Studio dynamic model discovery.** The [`opencode-models-discovery`](https://github.com/rivy-t/opencode-models-discovery) plugin currently emits `modalities.output: ["embedding"]` for LM Studio embedding models, which opencode's config schema rejects (only `text|audio|image|video|pdf` allowed). LM Studio is excluded from the plugin's discovery as a workaround (`providers.exclude: ["lmstudio"]` in `opencode-defaults.jsonc`); the documented default model is hard-declared. File an upstream issue, drop the exclusion when fixed.