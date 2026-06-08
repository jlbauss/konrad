# CLAUDE.md

Guidance for AI agents working on Konrad's source. (Konrad's *runtime* agent
behavior lives in `image/opencode/`, not here.) Canonical homes for everything
else — link, don't restate: [README.md](README.md) (users) · [CONTRIBUTING.md](CONTRIBUTING.md)
(dev + release process) · [ARCHITECTURE.md](ARCHITECTURE.md) (design + *why*) ·
[ROADMAP.md](ROADMAP.md) (backlog) · [CHANGELOG.md](CHANGELOG.md) (released changes).

## What this repo is

`bin/konrad` is a host CLI that runs [opencode](https://github.com/sst/opencode) in
a sandboxed Podman container. The image is the canonical artifact; the CLI is the
primary consumer. Full design: [ARCHITECTURE.md](ARCHITECTURE.md).

## Validating a change (no automated tests)

```sh
shellcheck bin/konrad image/entrypoint.sh scripts/*.sh        # lint — keep clean
bash -n <script>                                              # parse check
konrad-dev --rebuild && ./scripts/smoke-test.sh konrad:local  # build + smoke
konrad-dev --shell                                            # poke around the image
```

Anything under `image/` is baked and needs `konrad-dev --rebuild` before it takes
effect (skills, agents, `environment.md`, Dockerfile, deps). `bin/konrad`,
`scripts/`, and `.devcontainer/` are live — no rebuild. Dev loop and the
`konrad`/`konrad-dev` split: [CONTRIBUTING.md](CONTRIBUTING.md).

## Quick facts

- Config layering is `baked < org < user`, merged by [image/merge-config.js](image/merge-config.js): **objects merge, arrays replace.** So add agent rules via `AGENTS.md`, never by overriding the `instructions` array — the org `AGENTS.md` is the one exception (appended post-merge so array-replace can't drop it). Rationale: [ARCHITECTURE.md → Configuration & instructions](ARCHITECTURE.md#configuration--instructions).
- Runtime environment — tool inventory, the `/opt/venv` Python venv (`uv pip install` to extend), Debian renames (`fd`→`fdfind`, `bat`→`batcat`), locale — is manifested in [image/opencode/environment.md](image/opencode/environment.md).
- Bundled skills live in `image/opencode/skills/` (`do-it-manually`, `spreadsheets`, `pdf`, `quality-assurance`); `quality-assurance` is the cross-skill verification cycle every producer skill invokes before reporting. Fonts catalogue: [pdf/references/fonts.md](image/opencode/skills/pdf/references/fonts.md).

## Working agreements

Durable rules for every agent in this repo — written here (not just in per-session
memory) so they travel with the repo to every machine. When the user gives a durable
rule or preference, add it here as a bullet — that's what this section is for.

### Naming & terminology
- "Konrad" the product, `konrad` the code: capitalized name in prose; lowercase in every command / path / image / package (`bin/konrad`, `~/.config/konrad/`, `ghcr.io/jlbauss/konrad`) — never recapitalize those.
- Say "quality assurance," not "QA," in prose under `image/opencode/`. Files kebab-case (`quality-assurance.md`), Python identifiers snake_case (`quality_assurance_helpers.py`).

### Docs
- One audience per file; one canonical home per fact; others link, never duplicate. The map is the Repository guide in [ARCHITECTURE.md](ARCHITECTURE.md#repository-guide). User/project `AGENTS.md` overlays are additive, never replacements.
- When a ROADMAP item ships: add a terse [CHANGELOG.md](CHANGELOG.md) entry (Keep a Changelog) and delete the tier bullet, same commit. The changelog stays terse — rationale lives in the commit + ARCHITECTURE, never restated. Doc/CI/contributor-only changes (no `VERSION` bump) usually need no entry.
- Use the `docs(roadmap)` prefix for ROADMAP-only edits — agent commits append a one-line "what changed" note (no body); batch a session's edits and `--amend` before pushing, never after.

### Commits, versioning & release
- Canonical in [CONTRIBUTING.md](CONTRIBUTING.md): [Conventional Commits 1.0.0](CONTRIBUTING.md#commit-style), [SemVer + the tag scheme](CONTRIBUTING.md#versioning), and the branch→develop→bump→merge flow. Agent deltas: the `Co-Authored-By` trailer is **mandatory** on agent commits; multi-line body for any design decision; separate commits per concern; bump `VERSION` as the last commit before merge.
- Two version mechanics to know: the README version badge auto-derives from `VERSION` (a shields *dynamic* badge — don't replace it with a hardcoded one); and CLI/image version drift on CLI-only patches is expected — `VERSION` bumps without firing an image rebuild (the `image/**` filter), and `konrad --version` prints both with no warning. Bundle a CLI change that genuinely needs a new image into one `image/**`-touching commit.

### Editing safely
- Keep `bin/konrad` (and `image/entrypoint.sh`, `scripts/*.sh`) executable: a `644` `bin/konrad` breaks `konrad-dev`, so `chmod +x` after any rewrite that drops the bit and verify with `ls -l`.
- Validate smoke locally before pushing CI changes (`scripts/smoke-test.sh`, `image/Dockerfile`, `image/build-manifest.sh`): `konrad-dev --rebuild && ./scripts/smoke-test.sh konrad:local` beats a CI round-trip.
- Prefer `trash` over `rm` inside `/workspace` — it survives rebuilds and is recoverable (`trash-restore` / `trash-list`). `rm` hard-deletes; use it deliberately.

### Tooling & shell discipline
- Prefer the Read/Grep/Glob tools over `cat`/`grep`/`ls`/`find` in Bash — they never prompt. Keep Bash calls statically allow-able: no `$(…)` / backticks, no long `;` / `||` chains (the permission matcher can't prove those safe, so the whole call prompts). When a specific safe command prompts repeatedly, add a precise `Bash(<cmd>:*)` rule (the `fewer-permission-prompts` skill spots these) — never widen to cover `$(…)`.

### Self-testing the runtime (from the dev container)
- The `.devcontainer` mounts the host podman socket (`CONTAINER_HOST`), so `konrad-dev --rebuild` / `--shell` and workspace runs drive the host daemon directly. **Guard-rail: that's full host podman control — no `--privileged`, no host-path mounts; `podman push` stays `ask`.** Prereq (Linux): `systemctl --user enable --now podman.socket`. Linux-host only — see [CONTRIBUTING.md](CONTRIBUTING.md) for the macOS gap.
- End-to-end agent runs pin one cheap model, isolated from the user's state: `konrad-dev --profile selftest run --model openrouter/qwen/qwen3.6-27b "<prompt>"` — pass the model explicitly (don't inherit the host's persisted choice), and use `--profile` so the user's real state/model is untouched. Needs an OpenRouter key in the secrets volume.

### Engineering ethos
- Lightweight, composed, low-maintenance; simple over clever; resist sprawl. Stack well-maintained building blocks over bespoke code; configure rather than ship code; drive maintenance toward zero. Treat surprising or illogical behavior as a smell to fix at the source, not work around. Flag any change that adds custom code, a new maintenance surface, or sprawl. Full statement: [ARCHITECTURE.md → Engineering ethos](ARCHITECTURE.md#engineering-ethos--lightweight-composed-low-maintenance).

### Working with the user
- Don't commit until the user has read your explanation: present the write-up, let them read it, wait for "go," *then* commit — except trivial, already-agreed mechanical commits.
