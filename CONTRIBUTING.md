# Contributing to konrad

Thanks for your interest. Konrad is early-stage / alpha software — the runtime works, the daily-rebuild CI works, but the surface area is still moving and the docs lag the code in spots. Contributions of all sizes are welcome, especially the ones that surface gaps before more users do.

## Before you start

If you're proposing something larger than a typo fix, **open a GitLab issue first** to discuss. A short "I'd like to add X — does that fit?" conversation saves rework when the maintainer would have steered you elsewhere. For tiny things (typos, broken links, obvious one-line bugs), skip straight to a merge request.

What "larger" means in practice:

- A new bundled skill or agent
- A new CLI subcommand or flag
- Any change to config layering, state isolation, or the entrypoint
- Any non-trivial Dockerfile change

What does *not* need an issue first:

- Documentation fixes
- Tightening shellcheck cleanliness
- Adding a missing case to the smoke test
- Floating-pin maintenance (the daily CI normally handles this, but manual PRs are welcome too)

## What you're agreeing to

By submitting a PR you agree your contributions are licensed under **AGPL-3.0-or-later** (see [LICENSE](LICENSE)). Konrad is strong-copyleft on purpose — anyone running it (including over a network) has to publish their source. If that's incompatible with your situation, please don't submit.

No CLA, no DCO. The license terms attach automatically.

Licensing follows the [REUSE](https://reuse.software) spec, verified by `reuse lint`. **Add an SPDX header to every new or edited source file** — two comment lines near the top:

```text
# SPDX-FileCopyrightText: 2026 Your Name
# SPDX-License-Identifier: AGPL-3.0-or-later
```

Vendored third-party files keep their *upstream* `SPDX-FileCopyrightText` + license instead. Files that can't carry a comment (fonts, other binaries) and the project default are handled by globs in [`REUSE.toml`](REUSE.toml); when you introduce a new license, add its text under `LICENSES/` (`reuse download <SPDX-ID>`). Keep `reuse lint` green — CI enforces it.

## First-time setup

Konrad keeps the user CLI and the dev CLI as separate binaries on `PATH`, so you can hack on the source without disturbing your day-to-day stable `konrad`:

| Binary       | Source of CLI                  | Default image  | Refresh with                |
| ------------ | ------------------------------ | -------------- | --------------------------- |
| `konrad`     | Standalone install (curl\|sh)  | `konrad:latest` | `konrad --update`          |
| `konrad-dev` | Symlink to your checkout       | `konrad:local`  | `konrad-dev --rebuild`     |

Same script under the hood — `bin/konrad` picks its default image from `basename "$0"`. The two never collide, and you only need both if you want a stable agent alongside an in-flight dev build.

```sh
# 1. The user CLI (skip if you already have it).
curl -fsSL https://gitlab.git.nrw/jbauss2/konrad/-/raw/main/scripts/install-remote.sh | sh

# 2. The dev CLI.
git clone https://gitlab.git.nrw/jbauss2/konrad.git
cd konrad
mkdir -p ~/.local/bin && ln -sfn "$(pwd)/bin/konrad" ~/.local/bin/konrad-dev

# 3. Build the dev image and smoke-test.
konrad-dev --rebuild
./scripts/smoke-test.sh konrad:local
```

You need:

- Podman (Linux/macOS host; Docker is on the roadmap but not supported yet)
- `~/.local/bin` on your `$PATH`

The repo ships a Dev Container at `.devcontainer/` — "Reopen in Container" in VS Code gives you a portable edit-and-lint environment (shellcheck, hadolint, actionlint, jq, git, ripgrep, the Claude Code extension preinstalled). **`konrad-dev` is preprovisioned here** — the image symlinks it into `/usr/local/bin` (already on `PATH`), so the manual step 2 above is *only* for a native checkout; in the container you can run `konrad-dev --rebuild` straight away. It also mounts the host's rootless Podman socket, so `konrad-dev --rebuild`, `konrad-dev --shell`, and most of `./scripts/smoke-test.sh konrad:local` run **from inside the container** against the host's Podman daemon — no privileged Podman-in-container needed. **Runtime self-testing works on Linux and macOS hosts**, after a one-time prerequisite per OS. Linux: enable the socket once with `systemctl --user enable --now podman.socket`. macOS: point the Dev Containers extension at the rootful-connection shim — add to your VS Code **user** settings JSON: `"dev.containers.dockerPath": "/Users/you/.local/bin/podman-vscode.sh"` (run `echo ~/.local/bin/podman-vscode.sh` for the exact path; have the podman machine running). `initializeCommand` installs the shim to that stable path, so the same setting keeps working across konrad and any config-layer repo that reuses this dev container, without changing when you switch projects. One-time bootstrap on a fresh machine: VS Code probes `dockerPath` *before* running `initializeCommand`, so run `sh .devcontainer/ensure-podman-sock.sh` once by hand before the first container open (it self-refreshes on every open thereafter). The shim creates the dev container via the machine's bundled rootful connection — the only daemon whose API socket a nested container can reach (full rationale in [.devcontainer/podman-vscode.sh](.devcontainer/podman-vscode.sh)); your machine's *default* connection stays rootless, so day-to-day `podman` and `konrad` on the Mac are untouched. Two macOS side effects to know: the dev container and its named volumes live in the rootful daemon's separate store, so the first reopen starts fresh (Claude Code re-login, extensions reinstall — once); and self-tests there exercise a rootful daemon, so rootless-specific behavior (uid semantics, networking, limits) still needs a Linux run. On either OS the remote daemon resolves bind-mount paths on its own side, so konrad translates them to their real host paths: the `/workspace` mount and your config layer (`~/.config/konrad`, bound into the dev container and re-mounted into the runtime container) both come through, so a self-test composes `baked < org < user` and uses your real model / agents / skills exactly like a normal run. Only the host-side log dir is skipped (no daemon-visible path), and the smoke test's own org-layer check is skipped there (it bind-mounts a throwaway `/tmp` dir the daemon can't see — covered by CI on a local daemon instead). Without the prerequisite the container still starts — podman calls just fail cleanly (build/lint/edit all keep working).

## Local development loop

```sh
# Edit files...
konrad-dev --rebuild                                      # builds konrad:local
konrad-dev --shell                                        # exercise the dev image
shellcheck bin/konrad image/entrypoint.sh scripts/*.sh    # lint
./scripts/smoke-test.sh konrad:local                      # smoke (image artifact)
./scripts/selftest.sh                                     # end-to-end (image + a real run)
```

`konrad-dev` defaults to the `konrad:local` image (the one its own `rebuild` writes), so you exercise your dev build with no env var fiddling. The stable `konrad` next to it on `PATH` keeps pointing at `konrad:latest` — your day-to-day agent work is unaffected by whatever you're testing.

There's no traditional unit-test suite. The validation gates are:

- `bash -n <script>` — parse check
- `shellcheck <script>` — static analysis, should stay clean
- `./scripts/build-image.sh` — does the image build?
- `./scripts/smoke-test.sh konrad:local` — does the image have the right binaries / Python deps / baked content, and does the docling round-trip work? CI runs this same script. (Engine-agnostic and deliberately `bin/konrad`-free — CI runs it under Docker, and it validates the *image artifact*, not the host CLI. From a dev container against a remote daemon it skips the one bind-mount-based check, the org-layer compose, since that resolves daemon-side and is already covered by CI on a local daemon.)
- `./scripts/selftest.sh` — the realistic end-to-end loop, and the right gate to hand an agent: it runs the smoke test, then drives a real `konrad run` *through `bin/konrad`* (uid mapping, workspace mount, config compose — the path a user actually takes) and asserts the agent answers. By default the **model comes from your own `~/.config/konrad` config**, the same place normal konrad reads it — the self-test mounts that layer into the runtime container — so set it there once and both modes honor it. Override per run with `--model <slug>` or `KONRAD_SELFTEST_MODEL` (any provider — LM Studio, OpenRouter, …). It **degrades**: with no usable model/credential it still validates container startup and reports the model stage as SKIP, so a red result means the *runtime* broke, not that you haven't configured a model or wired a key. Not a CI gate (needs a model + credential). **One-time credential setup:** the run shares the `konrad-secrets` volume; populate it once by launching `konrad-dev` and running `/connect`. On macOS the rootful dev-container daemon has its *own*, initially-empty secrets volume (separate from your day-to-day rootless `konrad`), so do the `/connect` from inside the dev container.
- A live poke: `cd /tmp/konrad-test && konrad-dev --version` then `konrad-dev --shell` to look around. Dump the full build manifest with `podman run --rm --entrypoint cat konrad:local /etc/konrad/build-manifest.json | jq .`.

**Always smoke-test locally before pushing changes that touch `image/`, `scripts/smoke-test.sh`, or `image/build-manifest.sh`.** CI catches the bug eventually but at a ~10 min round-trip cost per iteration vs. ~5.5 min locally (rebuild + smoke).

## Branching and pull requests

Trunk-based: `main` is always deployable — what's at `ghcr.io/jlbauss/konrad:latest` mirrors `main`'s current state. The primary repo is **GitLab** (`gitlab.git.nrw/jbauss2/konrad`, public). The GitHub mirror is a **private CI execution surface only** — it exists because gitlab.git.nrw's shared runners can't run the privileged Podman build (see [ARCHITECTURE.md](ARCHITECTURE.md)). You never need a GitHub account to contribute.

**Maintainer** (direct repo access) — trunk-based via the git CLI, no MR ceremony. The canonical loop is **branch → develop → bump → merge**:

1. **Branch** off main: `git checkout -b feat/short-name`
2. **Develop** and commit.
3. **Bump** `VERSION` as the *last commit before merging*, not up front — with ff-only the branch tip becomes `main`, so a late bump keeps the version matching the integrated change and shrinks the window where two in-flight branches collide on the `VERSION` line (what to bump: [Versioning](#versioning)).
4. **Merge**: `git checkout main && git merge --ff-only feat/short-name && git push origin main`

For a higher-risk change, optionally push the branch to the private GitHub mirror and open a PR there to get a `:pr-<num>` test image first (see *Testing a change as an image* below); merge on GitLab once it checks out.

**Collaborators** (have GitLab repo access) — branch on the repo, push, then either hand the maintainer the branch to fast-forward, or open a **GitLab MR** if you want a review thread.

**External contributors** (the public) — everything happens on GitLab:

1. **Fork** the GitLab repo and branch off `main`.
2. Commit (bump `VERSION`, follow the commit style below) and push to your fork.
3. Open a **GitLab MR** against `main` — that's the review surface.
4. A fork MR gets human review automatically, but **no automatic image build**: the build runs on the GitHub mirror, which only mirrors the main repo's branches, not fork MRs. When the change is worth exercising in a container, the maintainer pulls your branch in (or pushes it to the mirror as `pr/<num>`) to produce a `:pr-<num>` image.
5. The maintainer merges on GitLab.

**Testing a change as an image** (`:pr-<num>`). PR builds go through the same build → smoke gate as `main` but publish *only* to `:pr-<num>` — never `:latest` or a release tag. Because the GHCR package is public, once a PR image exists anyone can pull and run it, no GitHub access needed:

```sh
podman pull ghcr.io/jlbauss/konrad:pr-<num>
KONRAD_IMAGE=ghcr.io/jlbauss/konrad:pr-<num> konrad --shell
```

Branch naming: `feat/<short>`, `fix/<short>`, `docs/<short>`, `chore/<short>`. Keep the slug short — the descriptive bit lives in the MR title.

## Versioning

The `VERSION` file at the repo root drives all image tagging. **Bump it in the same PR as your change.** Reviewer checks the bump matches the change's semver impact.

Pre-1.0 rules (where we are today): `VERSION` holds `0.X.Y`. Bump **`Y` (patch)** for a bug fix with no surface change; bump **`X` (minor)** for new functionality or any user-visible change, resetting `Y` to 0. Doc-only, CI-only, and ROADMAP-only changes don't bump.

Post-1.0, `VERSION` holds full semver `X.Y.Z`: **MAJOR** for a breaking change to the user-facing surface (config schema needing migration, a removed/renamed flag or bundled skill, a base-image major bump), **MINOR** for additive (new skill/flag/config slot/env var), **PATCH** for fixes and floating-pin refreshes. A commit's breaking marker (`!` / `BREAKING CHANGE:` — see [Commit style](#commit-style)) forces at least the corresponding bump. **1.0** is a deliberate event — when "no breaking change without a major bump" is a credible promise, roughly gated on the Tier-1 roadmap — not a date.

### Image tags

CI publishes each build to `ghcr.io/jlbauss/konrad` under several tags:

| Tag | Mutable? | Meaning |
|---|---|---|
| `:0.X.Y-YYYY-MM-DD` | immutable | the rollback handle — code `0.X.Y` + packages as of that day |
| `:0.X.Y` · `:0.X` · `:latest` | rolling | newest passing build for that patch / minor line / overall |
| `:pr-<num>` | per-PR | reviewer test image; never touches `:latest` or a release tag |
| `:<short-sha>` | immutable | per-commit, for bisecting |

The separator before the date is a **hyphen**, not a dot, so the tag doesn't read as a four-segment version. Post-1.0 the same shape gains a `:X` major-line tag.

### Git tags & releases

Releases live on **GitLab** — the GitHub mirror is CI-only, no releases there. Tags are **`vX.Y.Z`** (`v`-prefixed). The [`release` job in `.gitlab-ci.yml`](.gitlab-ci.yml) cuts the `v<VERSION>` tag + a GitLab Release automatically whenever a `chore(release):` bump to `VERSION` lands on main, pulling the release notes from the matching [CHANGELOG.md](CHANGELOG.md) section — which stays the authoritative record. So every `VERSION` bump (patch included) gets a tag; nothing to do by hand.

## Repo layout — what goes where

```text
konrad/
├── bin/konrad                         # The host-side CLI (the only thing on your PATH)
├── VERSION                            # Drives the image tag scheme (see versioning doc)
├── image/                             # Container build context — the canonical artifact
│   ├── Dockerfile                     # Pinning surface as a comment block at the top
│   ├── entrypoint.sh                  # Composes opencode.jsonc + layers user content at start
│   ├── merge-config.js                # Deep-merge for the JSONC config layering
│   ├── build-manifest.sh              # Snapshots apt/npm/pip versions → /etc/konrad/build-manifest.json
│   ├── locks/                         # Digest/version locks, one per build input (bot-maintained)
│   ├── konrad-defaults/               # → /etc/konrad/ (not opencode-discoverable)
│   │   └── opencode-defaults.jsonc    # Baked config defaults
│   ├── opencode/                      # → ~/.config/opencode/ in the image
│   │   ├── environment.md             # Runtime environment manifest (tools, libs, layout)
│   │   ├── agents/                    # Built-in primary agents (konrad, manual-transformer)
│   │   └── skills/                    # Bundled skills (do-it-manually, spreadsheets, pdf, quality-assurance)
│   └── fonts/konrad/                  # → /usr/local/share/fonts/konrad/ (seven OFL families)
├── scripts/
│   ├── build-image.sh                 # Local build (KONRAD_VERSION + GIT_SHA build args)
│   ├── smoke-test.sh                  # Smoke gate — CI runs this same script
│   ├── install-remote.sh              # curl|sh installer — fetches the CLI standalone, bakes VERSION in
│   └── fetch-fonts.sh                 # One-shot — pulls fonts from upstream when bumping versions
├── examples/org-package/              # Ready-to-adapt org-config starter (referenced from README)
├── .github/workflows/build-image.yml  # CI: build → smoke → publish (multi-arch amd64 + arm64)
├── .gitlab-ci.yml                     # Lock-resolver bot (source of truth; mirrors to GitHub)
├── ARCHITECTURE.md                     # System design and the *why* (consolidated)
├── CHANGELOG.md                       # Released-change log (Keep a Changelog; agent-maintained)
├── ROADMAP.md                         # Backlog tiers (shipped work → CHANGELOG.md)
├── CLAUDE.md                          # Repo instructions for agents working ON konrad
├── REUSE.toml                         # Per-file copyright/license by glob (REUSE spec)
├── LICENSES/                          # SPDX license texts (REUSE)
└── .devcontainer/                     # VS Code Dev Container for working ON konrad (Claude Code preinstalled)
```

If a change touches multiple concerns, prefer separate commits per concern. The git log is the project's primary design history — keep it useful.

## Commit style

[Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/), applied fully — by discipline, checked at review (no tooling, exactly like the [VERSION](#versioning) bump).

```text
type(scope)?: imperative, lowercase subject, no trailing period

Body — expected for anything that needed a design decision: explain *why*
(surprising constraints, non-obvious tradeoffs), wrapped at ~72 cols. Don't
restate the diff; the git log is the project's primary design history.

BREAKING CHANGE: <what breaks + how to migrate>   (footer, when applicable)
Co-Authored-By: ...                               (when applicable)
```

**Types** — `feat` (new capability), `fix` (bug fix), `docs`, `refactor` (no behaviour change), `perf`, `test`, `build` (build system / deps), `ci`, `style` (formatting only), `chore` (housekeeping — locks, etc.), `revert`.

**Scope** — optional; use one where it adds signal, from: `cli`, `image`, `config`, `skills`, `devcontainer`, `ci`, `locks`, `roadmap`, `release`.

**Breaking changes** — mark with `!` after the type/scope (e.g. `feat!:`) and/or a `BREAKING CHANGE:` footer. This drives the version bump: **MINOR pre-1.0** (no MAJOR slot yet), **MAJOR post-1.0** — see [Versioning](#versioning).

**Release commit** — the `VERSION` bump is `chore(release): <version>`, made as the last commit before merge (see [the maintainer flow](#branching-and-pull-requests)).

## When to update what

**ROADMAP.md** — a real idea worth keeping but not doing now → add it. A decision we made and are sticking with → don't add it (commit message is enough). A known shortcoming we've accepted as a trade-off → add it, so it doesn't get forgotten. When a Tier-N item ships, delete its bullet and add a terse [CHANGELOG.md](CHANGELOG.md) entry in the same commit.

**CHANGELOG.md** — every user-facing change that ships under a `VERSION` bump → a terse entry under that version ([Keep a Changelog](https://keepachangelog.com/); agent-maintained, rationale stays in the commit). Doc/CI/contributor-only changes that don't bump usually don't need one.

**README.md** — anything that changes how a user installs, runs, or thinks about konrad. A new subcommand or flag. A new external dependency (e.g. a tool the user has to install on the host).

**CLAUDE.md** — this is the repo-level instructions file, loaded by Claude Code (and any other agent) working *on* konrad. Update when there's a new tool/file/directory the agent should know about, a new convention or constraint the agent should follow, or a structural change (config layering, state tiers, image stages). The runtime konrad agent's *environment manifest* lives separately at `image/opencode/environment.md` (baked into the image, loaded by opencode at runtime via the `instructions` config key); update that file when shipped tools, Python libraries, or the filesystem layout change.

Keep all three tight — every byte competes with task context inside the model's window.

## Code of conduct

Be kind, be specific, assume good faith. We follow the [Contributor Covenant v2.1](https://www.contributor-covenant.org/version/2/1/code_of_conduct/). Report unacceptable behavior to the maintainer via private channel (email in the git log).

## Backlog and known gaps

See [ROADMAP.md](ROADMAP.md) for the full backlog and how items are prioritized — including the known shortcomings (Windows support, automated tests, multi-language UI) tracked there as accepted trade-offs. The user-facing [README Status section](README.md#status) summarises what to expect today.
