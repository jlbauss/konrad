# Roadmap & Backlog

## Inbox

_Raw ideas land here. Promote into ToDo after a refinement pass._

## ToDo

### Quality & UX (the differentiators)

- [ ] **Proper technical PDF skill.** Designed around the file type, not around docling. Subtasks: extract text/tables/images, edit existing PDFs, generate new PDFs (only the technical part, design skill comes later), fill forms. Replaces the current docling-shaped skill.
- [ ] **High-quality aspiration: no AI slop.** Konrad either produces a result he stands behind or tells the user he can't. Operationalize this with a QA subagent that reviews outputs against the original request before they're handed back, plus skill-level guidance for when "I can't do this cleanly" is the right answer. This is a positioning bet — the thing that separates Konrad from a generic local-agent wrapper.
- [ ] **Understanding → planning → refinement roundtrip.** Before executing, Konrad confirms he understands the user's goal — even when the user hasn't fully articulated it. A short clarifying loop ("here's what I think you want, here's the plan, anything off?") that the user can short-circuit when they already know what they want. Pairs with the QA aspiration above.
- [ ] **Proper spreadsheet skill.** Covers `.xlsx`, `.ods`, and `.csv` with a single mental model. Read, write, transform, with UTF-8 and locale-aware number/date handling baked in. Include the third UTF-8 defense layer here: a post-write validator that scans the output for mojibake byte sequences (`Ã¼`, `Ã¶`, `Â`, `Ã©`, U+FFFD) and aborts rather than handing back garbage. Cheap (~10 lines) and the right home for it, since this skill is the canonical owner of "the correct way to handle tabular files."
- [ ] **Plan visibility via TodoWrite.** Integrate the `planning-with-files` skill with `TodoWrite` so the user sees the live todo list in the UI as Konrad works through a multi-step task, instead of having to ask "where are you."
- [ ] **Polish the `konrad` CLI into something delightful.** Today `bin/konrad` is functional: subcommands work, help text is correct, errors print sensibly. "Exceptionally nice" is a step beyond — friendlier first-run experience (Podman missing? print the install one-liner, not just an error), progress feedback during the long `konrad rebuild` operation, shell completion for bash/zsh/fish, error messages that name the *fix* rather than just the *symptom*, and a `konrad doctor` subcommand that runs preflight diagnostics. The CLI is the first surface every user touches; it should feel cared-for.
- [ ] **Font assets out of the git tree.** Whatever fonts the bundled skills need shouldn't live as binary blobs in the repo. Deliver via LFS, a release tarball, or download-on-first-use, so cloning Konrad stays light and font updates don't churn git history.

### Build & runtime

- [ ] **Always-fresh build.** Rework the image build so every rebuild picks up the latest versions of opencode, the SDK packages, and base tools. Today versions drift silently between rebuilds. Tied to the version-pinning question below — pick one strategy.
- [ ] **Decide on version pinning.** Right now `autoupdate: false` plus unpinned npm installs means we get whatever was latest at image build time, frozen until next rebuild. Decide: pin everything and bump deliberately, or stay floating and rebuild often. Document the choice.
- [ ] **Local models work flawlessly.** End-to-end shakedown on LM Studio, Ollama, and llama.cpp with the recommended Qwen3.6-class models. Fix whatever rough edges remain (tool-call parsing, context overflow handling, model-switch UX).
- [ ] **Drop the `.agent` session-state requirement.** Konrad currently expects opencode session/working state inside `.agent`. Remove that coupling so the workspace doesn't get polluted with framework state.

### Distribution & security

- [ ] **Publish to a container registry.** GitLab CR with a CI workflow that rebuilds on Dockerfile changes and on a daily cadence. Unblocks the frictionless-install path.
- [ ] **Frictionless install.** A `curl … | sh` one-liner (or Homebrew tap) that drops `konrad` on `PATH` and pulls the image. Users shouldn't need to clone the repo.
- [ ] **Egress firewall.** A minimal allow-list firewall inside the container — block everything by default, allow only the configured provider endpoints and a small set of trusted hosts. Or a tiny sidecar container that does the same job at the network layer.
- [ ] **Security audit.** End-to-end review before declaring beta: container isolation, provider credential handling, MCP tool surface, file-system access boundaries.
- [ ] **Documentation pass.** Once the above is settled, rewrite the README and any in-repo docs so they describe the actual shipped product. Today they're partially aspirational.

## Future features

- [ ] **Multi-language support.** `AGENTS.md` and the bundled skill descriptions are English-only today. Ship localized variants (German first) — likely `AGENTS.<lang>.md` plus a setting in `~/.config/konrad/` to pick the active language, so a non-English user gets responses in their language without prompting for it every time.
- [ ] **Dev Container as a second consumption path.** `devcontainer/devcontainer.json` exists but is minimal and out of date — currently parked at top-level (not `.devcontainer/`) so VS Code doesn't auto-detect it. Bring it up to scratch and treat it as a first-class way to _use_ Konrad (open a workspace in VS Code, get a fully-wired Konrad) alongside the host CLI — not just a tool for working _on_ Konrad itself. When promoted, rename back to `.devcontainer/`.
- [ ] **Preconfigured MCP servers.** Ship `opencode.jsonc` with a working set of MCPs (filesystem, fetch, GitHub) wired up so the model has useful tools the moment it boots — no MCP setup tax on first-run.
- [ ] **Design skill (the aesthetic side).** The technical skills (PDF, slides, future docs) cover *how* to assemble an artifact — extract, generate, fill, transform. They deliberately don't cover whether the output *looks good*. A separate design skill owns visual quality — typography, layout, color, hierarchy, brand consistency — and composes with the technical skills when the user wants polished output rather than just functional output. Open scope question: advisor that critiques drafts, generator that produces themed templates, or both. Pairs with the "no AI slop" aspiration: a deck that's structurally correct but aesthetically broken is still slop.
- [ ] **More skills.** `.eml` email, Markdown authoring, HTML presentations.
- [ ] **Docker support.** Currently Podman-only because of `--userns=keep-id`. A Docker-compatible alternative `devcontainer.json` (or conditional `runArgs`) would broaden the audience.
- [ ] **Top-level CI.** JSON/JSONC schema validation for the opencode configs, `shellcheck` on bundled shell scripts, and an "image actually builds" smoke job.
- [ ] **Inline model discovery (replaces the dropped plugin).** Eventually replace the removed `opencode-models-discovery` plugin with ~30 lines of host-side bash in `bin/konrad` plus a small `jq` step in `image/entrypoint.sh` that writes the discovered providers as a runtime config override. Empirically the plugin cost ~3.7 s of Bun startup; doing it natively eliminates that without giving up the feature. Only worth doing once we've also resolved the LM Studio embedding-modality issue upstream (or accept the same exclusion in our inline version).

## Implemented

- [x] **README: recommend vision-enabled models.** Added a "Pick a vision-capable model if you'll touch images" bullet to the Requirements section, calling out the silent failure mode (text-only models hallucinate image content rather than refusing) and listing concrete options on LM Studio, Ollama, and hosted providers. The "konrad does not currently warn you" caveat is honest about today's limitation — eventual fix lives under the Quality & UX aspiration.
- [x] **UTF-8 everywhere on output (defense in depth).** Two layers landed: (1) the container runs at `LANG=C.UTF-8` / `LC_ALL=C.UTF-8`, so Python's `open()` and the locale-sensitive shell tools default to UTF-8 instead of POSIX/C — the silent root cause of most mojibake. (2) The `do-it-manually` skill now spells out its read/write encoding contract: recognize mojibake (`Ã¼`, `Ã¶`, etc.) as a content problem the calling agent has to decide on (repair vs. preserve), write outputs as UTF-8 with no BOM, and surface mojibake leakage in the suspicious-result QA scan. Layer 3 (post-write validator) is parked in the future spreadsheet skill, since that's the canonical owner of tabular-file correctness.
- [x] **Removed the `opencode-models-discovery` plugin.** Stripped the plugin declaration and the `lmstudio` exclusion from `opencode-defaults.jsonc`, the host-side reachability probe + `KONRAD_PROVIDER_EXCLUDES` plumbing from `bin/konrad`, and the runtime-override generation from `image/entrypoint.sh`. Config composition is now plain two-layer (baked + user) instead of three-layer. Cost the model auto-discovery feature; recouped ~3-4 s of Bun startup time and dropped a fragile upstream dependency. Inline replacement tracked under Future features.
- [x] **Codebase truth pass.** Reviewed every comment and print statement across the repo against current behavior. Fixed stale references to the removed `konrad-npm-global` volume, the non-existent "entrypoint LM-Studio probe", a missing README "Pinning strategy" section, the wrong source URL in the image OCI labels, and the "no skills ship" claim repeated in four docs. Bundled with the pass: deleted leftover `.agent/`, `scripts/.agent/`, and `.skill-eval/` (konrad isn't dogfooded for its own development today), and moved `.devcontainer/` to top-level `devcontainer/` so VS Code stops auto-detecting an experimental consumption path as the active dev environment.
- [x] **Custom opencode agent profiles.** Use opencode's `agents/` mechanism to ship a customized Konrad prompt instead of the default build and plan agents.
- [x] **Other providers.** Remove hard-coded lm-studio as provider.
- [x] **Improve image.** Optimize structure and size. Follow Node best practices: https://github.com/nodejs/docker-node/blob/main/docs/BestPractices.md Include more relevant tools.
- [x] **Make image provider-agnostic.** Currently only lm studio is supported and the model is hardwired. Make it configurable, also from the tui.
- [x] **User config directory at `~/.config/konrad/`.** A standard home-dir location where users keep their own konrad settings — preferred model, UI language, default agent mode, whatever else accumulates. `bin/konrad` reads it on startup; bind-mount the relevant pieces (or pass them as env vars) into the container. Subsumes the "end-user config override" item below as the canonical place those overrides live.
- [x] **opencode permission ACLs.** Use the `permission` block in `opencode.jsonc` to constrain which shell commands and tools the model can invoke without user confirmation.

## Obsolete

- [ ] **Specialized modes.** Add purpose-built modes — e.g. `konrad-default`, `konrad-perfectionist`.
- [ ] **Restore LM Studio dynamic model discovery.** The [`opencode-models-discovery`](https://github.com/rivy-t/opencode-models-discovery) plugin emits `modalities.output: ["embedding"]` for LM Studio embedding models, which opencode's config schema rejects. Superseded by removing the plugin entirely (see Implemented); the inline-discovery replacement is tracked under Future features.
