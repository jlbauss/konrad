<!--
SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
SPDX-License-Identifier: AGPL-3.0-or-later
-->

# CLAUDE.md

Guidance for AI agents working on Konrad's source. (Konrad's *runtime* agent
behavior lives in `image/opencode/`, not here.) Canonical homes for everything
else — link, don't restate: [README.md](README.md) (users) · [CONTRIBUTING.md](CONTRIBUTING.md)
(dev + release process) · [ARCHITECTURE.md](ARCHITECTURE.md) (design + *why*) ·
[ROADMAP.md](ROADMAP.md) (backlog) · [CHANGELOG.md](CHANGELOG.md) (released changes).

Very important: ALWAYS read the README, ROADMAP, CONTRIBUTING and ARCHITECTURE docs once before you start planning or building, so they are in your context and you are able to follow the instructions they give.

## What this repo is

`bin/konrad` is a host CLI that runs [opencode](https://github.com/sst/opencode) in
a sandboxed Podman container. The image is the canonical artifact; the CLI is the
primary consumer. Full design: [ARCHITECTURE.md](ARCHITECTURE.md).

## Validating a change (no automated tests)

```sh
shellcheck bin/konrad image/entrypoint.sh scripts/*.sh        # lint — keep clean
bash -n <script>                                              # parse check
konrad-dev rebuild && ./scripts/smoke-test.sh konrad:local  # build + smoke
konrad-dev shell                                            # poke around the image
```

Anything under `image/` is baked and needs `konrad-dev rebuild` before it takes
effect (skills, agents, `environment.md`, Dockerfile, deps). `bin/konrad`,
`scripts/`, and `.devcontainer/` are live — no rebuild. Dev loop and the
`konrad`/`konrad-dev` split: [CONTRIBUTING.md](CONTRIBUTING.md).

A **first/uncached `konrad-dev rebuild` needs real RAM** on the *daemon* it
builds against: the `python-models` stage pulls + processes ~1 GB of Docling
weights through torch and is OOM-killed (exit 137, `Killed`) under ~2 GB. The
build uses the daemon's full RAM — there is **no build `--memory` knob to raise**
(it's a ceiling, not a floor), so the fix is more daemon memory, not a flag: on
macOS `podman machine set --memory <MB>` (the build runs on the machine VM via
the bound socket); the `.devcontainer` declares its own `hostRequirements` for
orchestrated hosts. The model layer is byte-stable/commit-pinned, so a *warm*
rebuild skips this stage entirely — it only bites the first build or after a
cache wipe. On a too-small box, build in CI / on a bigger host instead.

## Quick facts

- Config layering is `baked < org₁ < … < user`, merged by [image/merge-config.js](image/merge-config.js): **objects merge, arrays replace.** `~/.config/konrad/org/` is a *container* of named layers (`org/<name>/`), each usually a git checkout the `konrad org` verbs manage host-side (managed mirrors, re-synced on `konrad update`; optional host-run `hooks/post-sync` — subscribing is trusting). Add model instructions by dropping a `*.md` into a layer's `instructions/` dir (or via `AGENTS.md`), never by overriding the `instructions` array. The baked `opencode.jsonc` declares globs only for the baked and user `instructions/` dirs; org layers can't be globbed (opencode globs only an entry's basename component), so the entrypoint *copies* their instruction files into the baked dir as `org-<name>-<file>`, where the baked glob finds them. Rationale: [ARCHITECTURE.md → Configuration & instructions](ARCHITECTURE.md#configuration--instructions).
- Runtime environment — tool inventory, the `/opt/venv` Python venv (`uv pip install` to extend), Debian renames (`fd`→`fdfind`, `bat`→`batcat`), locale — is manifested in [image/opencode/environment.md](image/opencode/environment.md).
- Bundled skills live in `image/opencode/skills/` (`pdf`, `spreadsheets`, `image-editing`, `frontend-design`, `do-it-manually`, `grill-me`, `write-a-skill`, `quality-assurance`); `quality-assurance` is the cross-skill verification cycle every producer skill invokes before reporting. Fonts catalogue: [pdf/references/fonts.md](image/opencode/skills/pdf/references/fonts.md).
- The agent's runtime tool `permission`s have **one home** — the baseline in [image/konrad-defaults/opencode-defaults.jsonc](image/konrad-defaults/opencode-defaults.jsonc); agent files (`agents/*.md`) carry **only deltas** (they deep-merge over it). The model is sandbox-shaped, not action-scariness-shaped — `ask` only on `rm -rf`, `deny` only the escape vectors, everything else `allow`. Don't re-add a full permission block to an agent. Rationale: [ARCHITECTURE.md → Configuration & instructions](ARCHITECTURE.md#configuration--instructions). (Not to be confused with the *host* Claude Code deny/ask lists in `.claude/` — a different layer, covered under Tooling & shell discipline below.)

## Working agreements

Durable rules for every agent in this repo — written here (not just in per-session
memory) so they travel with the repo to every machine. When the user gives a durable
rule or preference, add it here as a bullet — that's what this section is for.

### Naming & terminology

- "Konrad" the product, `konrad` the code: capitalized name in prose; lowercase in every command / path / image / package (`bin/konrad`, `~/.config/konrad/`, `ghcr.io/jlbauss/konrad`) — never recapitalize those.
- Say "quality assurance," not "QA," in prose under `image/opencode/`. Files kebab-case (`quality-assurance.md`), Python identifiers snake_case (`quality_assurance_helpers.py`).

### Docs

- One audience per file; one canonical home per fact; others link, never duplicate. The map is the Repository guide in [ARCHITECTURE.md](ARCHITECTURE.md#repository-guide). User/project `AGENTS.md` overlays are additive, never replacements.
- When a ROADMAP item ships: add a terse [CHANGELOG.md](CHANGELOG.md) entry (Keep a Changelog) and delete the roadmap bullet, same commit. The changelog stays terse — rationale lives in the commit + ARCHITECTURE, never restated. Doc/CI/contributor-only changes (no `VERSION` bump) usually need no entry.
- Use the `docs(roadmap)` prefix for ROADMAP-only edits — agent commits append a one-line "what changed" note (no body); batch a session's edits and `--amend` before pushing, never after.

### Commits, versioning & release

- Canonical in [CONTRIBUTING.md](CONTRIBUTING.md): [Conventional Commits 1.0.0](CONTRIBUTING.md#commit-style), [SemVer + the tag scheme](CONTRIBUTING.md#versioning), and the branch→develop→bump→merge flow. Agent deltas: the `Co-Authored-By` trailer is **mandatory** on agent commits; multi-line body for any design decision; separate commits per concern; bump `VERSION` as the last commit before merge.
- **Bumping `VERSION` is half a release — promote the CHANGELOG in the *same* commit.** Rename `## [Unreleased]` to `## [<version>] - <YYYY-MM-DD>` and open a fresh empty `## [Unreleased]` above it. The GitLab `release` job pulls notes from the `## [<version>]` section, so a bump that leaves the entries under `## [Unreleased]` ships an empty release. The job now **fails closed** on a missing section (so the slip breaks loudly, not silently), but don't rely on the net — do the promotion as part of the bump. Canonical: [CONTRIBUTING → Release commit](CONTRIBUTING.md#when-to-update-what).
- Two version mechanics to know: the README version badge auto-derives from `VERSION` (a shields *dynamic* badge — don't replace it with a hardcoded one); and CLI/image version drift on CLI-only patches is expected — `VERSION` bumps without firing an image rebuild (the `image/**` filter), and `konrad --version` prints both with no warning. Bundle a CLI change that genuinely needs a new image into one `image/**`-touching commit.
- **End-of-feature-branch handoff (and leave no stale branches).** `git push` is in the agent deny list, so when a feature branch is ready, *always* hand the user the exact ff-only sequence to run — don't make them ask: `git checkout main && git merge --ff-only <branch> && git push origin main && git branch -d <branch>` (append `git push origin --delete <branch>` only if it was ever pushed; local-only branches have no remote). That trailing `git branch -d` is what stops the *just-merged* branch from going stale — never omit it. To also catch *pre-existing* cruft, when you're finishing up in the repo, sweep: `git branch --merged main` → delete the merged leftovers with `git branch -d`; `git worktree list` → `git worktree prune` for any `prunable` entry. Never `-D` a branch that still has unmerged commits without asking — that work exists only in its branch. Canonical flow: [CONTRIBUTING → maintainer loop](CONTRIBUTING.md#branching-and-pull-requests).
- **Trivial edits skip the branch.** A contributor-only one-liner (a doc/rule tweak, no `VERSION` and no `image/**` change) can be committed straight to `main`; just hand over `git push origin main`. Reserve the branch→merge flow for actual changes. (After a handoff your shell may already be *on* `main` because the feature branch was merged + deleted out from under you — so for anything non-trivial, branch first rather than committing onto `main` by accident.)

### Editing safely

- Add an SPDX header to every **new or edited** source file: `# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß` + `# SPDX-License-Identifier: AGPL-3.0-or-later` (vendored files keep their *upstream* header). The repo follows REUSE; `reuse lint` (in the dev container; CI-enforced on GitLab) must stay green. Canon: [CONTRIBUTING → licensing](CONTRIBUTING.md#what-youre-agreeing-to).
- Keep `bin/konrad` (and `image/entrypoint.sh`, `scripts/*.sh`) executable: a `644` `bin/konrad` breaks `konrad-dev`, so `chmod +x` after any rewrite that drops the bit and verify with `ls -l`.
- Validate smoke locally before pushing CI changes (`scripts/smoke-test.sh`, `image/Dockerfile`, `image/build-manifest.sh`): `konrad-dev rebuild && ./scripts/smoke-test.sh konrad:local` beats a CI round-trip.
- Prefer `trash` over `rm` inside `/workspace` — it survives rebuilds and is recoverable (`trash-restore` / `trash-list`). `rm` hard-deletes; use it deliberately.
- Keep markdown **markdownlint-green** (like `reuse`/shellcheck): run `npx --yes markdownlint-cli2` before pushing doc changes; CI gates it. Rules live in `.markdownlint.jsonc` (the shared ruleset — config-layer repos symlink it, so a rule change here propagates on their next submodule bump), scope/ignores in `.markdownlint-cli2.jsonc`. The VS Code extension (`DavidAnson.vscode-markdownlint`) flags issues live. Baked `image/**` docs are deliberately out of scope — they ride intentional image rebuilds, not a docs linter.

### Tooling & shell discipline

- Prefer the Read/Grep/Glob tools over `cat`/`grep`/`ls`/`find` in Bash — they never prompt and read cleaner than shell. When you do shell out, keep each call a single statement: no `echo "--- … ---"; cmd; echo` diagnostic chains, no `$(…)` / backticks, no `;` / `||` chains. Bundling clutters the transcript and turns an otherwise-safe call into one the permission matcher can't prove safe — one command per call, let the tool output speak.
- Permission posture: the devcontainer runs Claude with `defaultMode: bypassPermissions`, written by its `postCreateCommand` (`.devcontainer/setup-claude-permissions.sh`) to the **container-only** user settings `~/.claude/settings.json` (a named volume) — *not* the project `.claude/settings.local.json`, which is a host bind mount a bare-host run would also read. So the bypass is invisible outside the container and never committed; the disposable container, not the prompt, is the boundary. Keep `defaultMode` out of committed settings (it would override user scope). That user-scope default only reaches **terminal** `claude` runs — the VS Code extension passes an explicit `--permission-mode` CLI flag (which beats every settings file), so the extension panel gets its bypass from the machine-scope `claudeCode.*` settings in devcontainer.json's `customizations.vscode.settings` (also container-only: they live on the `.vscode-server` volume; pre-existing-volume caveat documented there). The committed `deny` list (`git push`, secret reads) and `ask` list still apply under bypass — notably `podman run` stays `ask`, since a raw `podman run -v …` against the host socket is the one command that can escape the container (and on rootful macOS reach your Mac home). So prompts are rare by design; if a *new* safe command prompts on a bare-host or teammate run (no bypass there), add a precise `Bash(<cmd>:*)` rule to the committed allowlist (the `fewer-permission-prompts` skill spots these) — never widen to cover `$(…)`.

### Self-testing the runtime (from the dev container)

- The `.devcontainer` mounts the host podman socket (`CONTAINER_HOST`), so `konrad-dev rebuild` / `konrad-dev shell` and workspace runs drive the host daemon directly. **Guard-rail: that's full host podman control (on macOS: root on the podman-machine VM) — no `--privileged`, no host-path mounts; `podman push` stays `ask`.** One-time prereq — Linux: `systemctl --user enable --now podman.socket`; macOS: the `dev.containers.dockerPath` shim wire-up in [CONTRIBUTING.md](CONTRIBUTING.md) (the daemon there is the VM's rootful one; `bin/konrad` swaps keep-id for explicit uid maps when `KONRAD_DAEMON_ROOTFUL=1`).
- End-to-end runs go through `./scripts/selftest.sh` (smoke test + a real `konrad run` through `bin/konrad`, asserted). It isolates state via `--profile selftest` and degrades to a SKIP on the model stage when no model/credential is usable, so it's safe to run blind — a red result means the runtime broke, not that setup is missing. **The default model comes from your own `~/.config/konrad` config** (the self-test mounts that layer into the runtime container, so it composes `baked < org < user` like a normal run) — set it where you'd set it for normal konrad. Override per run with `./scripts/selftest.sh --model <slug>` or `KONRAD_SELFTEST_MODEL=…` (any provider, not OpenRouter-locked). The raw primitive it wraps is `konrad-dev --profile selftest run [--model <slug>] "<prompt>"`. To exercise the model stage, the shared `konrad-secrets` volume needs a provider credential (`konrad-dev` → `/connect`); on macOS that's the rootful daemon's own secrets volume.

### Engineering ethos

- Lightweight, composed, low-maintenance; simple over clever; resist sprawl. Stack well-maintained building blocks over bespoke code; configure rather than ship code; drive maintenance toward zero. Treat surprising or illogical behavior as a smell to fix at the source, not work around. Flag any change that adds custom code, a new maintenance surface, or sprawl. Full statement: [ARCHITECTURE.md → Engineering ethos](ARCHITECTURE.md#engineering-ethos--lightweight-composed-low-maintenance).

### Working with the user

- Don't commit until the user has read your explanation: present the write-up, let them read it, wait for "go," *then* commit — except trivial, already-agreed mechanical commits.
- **Nothing ships on inspection alone — you supply the real-life probe, with a baseline.** No automated tests here, so every build finishes with explicit real-life test/probe instructions as part of the handoff; never declare something done because the code reads right. Each probe must first establish a **baseline that proves the test environment itself is correct** (the control — the expected-good path works, so you know you're testing the right thing), *then* change only the one variable under test, so a pass actually isolates what you built. E.g. the seal: first confirm the proxy path works and the environment is sane, *then* show the direct host route is refused — a refusal proves nothing if you never proved access was possible to begin with.
- **Batch everything that needs the user to the end; maximize unattended runtime.** The goal is to run as long as possible without interrupting the user. Don't stop mid-task for input you could defer — prefer a sensible default plus a note over a mid-run question. Collect every item that genuinely needs them (the ff-only merge handoff, `/connect` for credentials, the real-life probes above, any host-side command the agent can't run) and present them together as one batch when the work is done.
- **Prefer the repo's own docs over per-session memory.** Durable knowledge belongs where it travels with the repo and survives to every machine and teammate — a rule here in CLAUDE.md, or the relevant canonical doc ([ARCHITECTURE.md](ARCHITECTURE.md), [CONTRIBUTING.md](CONTRIBUTING.md), [ROADMAP.md](ROADMAP.md), an `AGENTS.md`). So don't reach for a private memory file by default; when something is worth remembering, *offer* to write it into CLAUDE.md or the right doc and let the user say where. Reserve memory for genuinely machine-local, non-shareable context.
