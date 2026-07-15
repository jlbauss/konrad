# Contributing to konrad

Thanks for your interest. Konrad is beta software — the runtime and the daily-rebuild CI are solid, but the pre-1.0 surface area is still moving and the docs can lag the code in spots. Contributions of all sizes are welcome, especially the ones that surface gaps before more users do.

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
| `konrad`     | Standalone install (curl\|sh)  | `konrad:latest` | `konrad update`          |
| `konrad-dev` | Symlink to your checkout       | `konrad:local`  | `konrad-dev rebuild`     |

Same script under the hood — `bin/konrad` picks its default image from `basename "$0"`. The two never collide, and you only need both if you want a stable agent alongside an in-flight dev build.

```sh
# 1. The user CLI (skip if you already have it).
curl -fsSL https://gitlab.git.nrw/jbauss2/konrad/-/raw/main/scripts/install.sh | sh

# 2. The dev CLI.
git clone https://gitlab.git.nrw/jbauss2/konrad.git
cd konrad
mkdir -p ~/.local/bin && ln -sfn "$(pwd)/bin/konrad" ~/.local/bin/konrad-dev

# 3. Build the dev image and smoke-test.
konrad-dev rebuild
./scripts/smoke-test.sh konrad:local
```

You need:

- A container engine — **Podman** on Linux (and the dev container), or Apple's **`container`** on Apple-Silicon macOS 26+. `konrad-dev rebuild` builds on whichever it runs on: Podman via buildah, apple/container via `container build` (straight into its own store — no Podman or `podman machine` VM needed on the Mac). Pin with `KONRAD_ENGINE=podman|container`. Docker is on the roadmap but not supported yet.
- `~/.local/bin` on your `$PATH`

The repo ships a Dev Container at `.devcontainer/` — "Reopen in Container" in VS Code gives you a portable edit-and-lint environment (shellcheck, hadolint, actionlint, jq, git, ripgrep, the Claude Code extension preinstalled), with **`konrad-dev` already on `PATH`** — the manual step 2 above is only for a native checkout. It also mounts the host's Podman socket, so `konrad-dev rebuild`, `konrad-dev shell`, and the smoke test run **from inside the container** against the host daemon — no privileged Podman-in-container needed, and a self-test composes `baked < org < user` with your real config, exactly like a normal run.

One-time prerequisite per OS for that runtime self-testing:

- **Linux:** `systemctl --user enable --now podman.socket`
- **macOS:** point the Dev Containers extension at the rootful-connection shim — add `"dev.containers.dockerPath": "/Users/you/.local/bin/podman-vscode.sh"` to your VS Code **user** settings (run `echo ~/.local/bin/podman-vscode.sh` for the exact path) and run `sh .devcontainer/ensure-podman-sock.sh` once before the first container open. Why a shim and how it works: header of [.devcontainer/podman-vscode.sh](.devcontainer/podman-vscode.sh). Two side effects: the rootful daemon keeps separate stores, so the first reopen starts fresh (one-time Claude Code re-login) and the runtime needs its own `/connect`; and self-tests there exercise a *rootful* daemon, so rootless-specific behavior (uid semantics, networking, limits) still needs a Linux run.

Without the prerequisite the container still starts — podman calls just fail cleanly (build/lint/edit all keep working).

## Local development loop

```sh
# Edit files...
konrad-dev rebuild                                      # builds konrad:local
konrad-dev shell                                        # exercise the dev image
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
- `./scripts/selftest.sh` — the realistic end-to-end loop, and the right gate to hand an agent: it runs the smoke test, then drives a real `konrad run` *through `bin/konrad`* (uid mapping, workspace mount, config compose — the path a user actually takes) and asserts the agent answers. The **model comes from your own `~/.config/konrad` config** (override with `--model <slug>` / `KONRAD_SELFTEST_MODEL`, any provider); with no usable model/credential the model stage degrades to a SKIP, so a red result always means the *runtime* broke. One-time: populate the shared `konrad-secrets` volume via `konrad-dev` → `/connect` (on macOS from inside the dev container — the rootful daemon has its own volume). Not a CI gate.
- A live poke: `cd /tmp/konrad-test && konrad-dev --version` then `konrad-dev shell` to look around. Dump the full build manifest with `podman run --rm --entrypoint cat konrad:local /etc/konrad/build-manifest.json | jq .`.

**Always smoke-test locally before pushing changes that touch `image/`, `scripts/smoke-test.sh`, or `image/build-manifest.sh`.** CI catches the bug eventually but at a ~10 min round-trip cost per iteration vs. ~5.5 min locally (rebuild + smoke).

## Branching and pull requests

Trunk-based: `main` is always deployable — what's at `ghcr.io/jlbauss/konrad:latest` mirrors `main`'s current state. The primary repo is **GitLab** (`gitlab.git.nrw/jbauss2/konrad`, public). The GitHub mirror is **public for discoverability, but CI-and-releases only** — it exists because gitlab.git.nrw's shared runners can't run the privileged Podman build (see [ARCHITECTURE.md](ARCHITECTURE.md)), and [mirror-release.yml](.github/workflows/mirror-release.yml) recreates each GitLab release there off the mirrored tag. Contributions happen on GitLab; you never need a GitHub account to contribute.

**Maintainer** (direct repo access) — trunk-based via the git CLI, no MR ceremony. The canonical loop is **branch → develop → bump → merge**:

1. **Branch** off main: `git checkout -b feat/short-name`
2. **Develop** and commit.
3. **Bump** `VERSION` as the *last commit before merging*, not up front — with ff-only the branch tip becomes `main`, so a late bump keeps the version matching the integrated change and shrinks the window where two in-flight branches collide on the `VERSION` line (what to bump: [Versioning](#versioning)).
4. **Merge**: `git checkout main && git merge --ff-only feat/short-name && git push origin main`

For a higher-risk change, optionally push the branch to the GitHub mirror and open a PR there to get a `:pr-<num>` test image first (see *Testing a change as an image* below); merge on GitLab once it checks out.

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
KONRAD_IMAGE=ghcr.io/jlbauss/konrad:pr-<num> konrad shell
```

Branch naming: `feat/<short>`, `fix/<short>`, `docs/<short>`, `chore/<short>`. Keep the slug short — the descriptive bit lives in the MR title.

## Versioning

The `VERSION` file at the repo root drives all image tagging. **Bump it in the same PR as your change.** Reviewer checks the bump matches the change's semver impact.

Pre-1.0 rules (where we are today): `VERSION` holds `0.X.Y`. Bump **`Y` (patch)** for a bug fix with no surface change; bump **`X` (minor)** for new functionality or any user-visible change, resetting `Y` to 0. Doc-only, CI-only, and ROADMAP-only changes don't bump.

Post-1.0, `VERSION` holds full semver `X.Y.Z`: **MAJOR** for a breaking change to the user-facing surface (config schema needing migration, a removed/renamed flag or bundled skill, a base-image major bump), **MINOR** for additive (new skill/flag/config slot/env var), **PATCH** for fixes and floating-pin refreshes. A commit's breaking marker (`!` / `BREAKING CHANGE:` — see [Commit style](#commit-style)) forces at least the corresponding bump. **1.0** is a deliberate event — when "no breaking change without a major bump" is a credible promise, roughly gated on the roadmap's **Next** section — not a date.

### Image tags

CI publishes each build to `ghcr.io/jlbauss/konrad` under several tags:

| Tag | Mutable? | Meaning |
|---|---|---|
| `:0.X` | rolling | newest passing build on the minor line — the **pin-a-line** handle: get patches, stop at the next `X`. Post-1.0 becomes `:X` (major line). |
| `:latest` | rolling | newest passing build overall — the **only tag the CLI reads** (`konrad update` pulls this) |
| `:<short-sha>` | **immutable** | the one per-build handle that never moves — maps 1:1 to a commit. Use it for rollback, bisecting, and `scripts/layer-diff.sh`. |
| `:pr-<num>` | per-PR | reviewer test image; never touches `:latest` or a line tag |

There is deliberately **no version- or date-derived image tag**. `VERSION` drives the *CLI*, not image content — a CLI-only patch bumps `VERSION` without firing an image rebuild ([the `image/**` paths filter](.github/workflows/build-image.yml)) — so an image-side `:0.X.Y` would promise a precision the build can't keep, and a `:0.X.Y-DATE` tag isn't immutable (two builds the same day overwrite it). The honest immutable handle is `:<short-sha>`; `konrad --version` prints it as the image identity. To pin an exact image, pin the SHA.

### Git tags & releases

Releases are cut on **GitLab** — the authoritative record — and mirrored to GitHub automatically: [mirror-release.yml](.github/workflows/mirror-release.yml) fires on each mirrored `v*` tag and recreates the release from the same CHANGELOG section (its `workflow_dispatch` backfills any tag that's missing one). Tags are **`vX.Y.Z`** (`v`-prefixed). The [`release` job in `.gitlab-ci.yml`](.gitlab-ci.yml) cuts the `v<VERSION>` tag + a GitLab Release automatically whenever a `chore(release):` bump to `VERSION` lands on main, pulling the release notes from the matching [CHANGELOG.md](CHANGELOG.md) section — which stays the authoritative record. So every `VERSION` bump (patch included) gets a tag; nothing to do by hand **except promote the CHANGELOG section in the bump commit** (see [Release commit](#when-to-update-what)) — the job fails closed if `## [<VERSION>]` is missing.

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
│   │   ├── instructions/              # Baked layer's system-instructions dir
│   │   │   └── environment.md         # Runtime environment manifest (tools, libs, layout)
│   │   ├── agents/                    # Built-in primary agents (konrad, manual-transformer)
│   │   └── skills/                    # Bundled skills (pdf, spreadsheets, image-editing, frontend-design, do-it-manually, grill-me, write-a-skill, quality-assurance)
│   └── fonts/konrad/                  # → /usr/local/share/fonts/konrad/ (seven OFL families)
├── scripts/
│   ├── build-image.sh                 # Local build (KONRAD_VERSION + GIT_SHA build args)
│   ├── smoke-test.sh                  # Smoke gate — CI runs this same script
│   ├── install.sh              # curl|sh installer — fetches the CLI standalone, bakes VERSION in
│   └── fetch-fonts.sh                 # One-shot — pulls fonts from upstream when bumping versions
├── examples/org-package/              # Git-native org-layer example repo (referenced from README)
├── .github/workflows/build-image.yml  # CI: build → smoke → publish (multi-arch amd64 + arm64)
├── .gitlab-ci.yml                     # Lock-resolver bot (source of truth; mirrors to GitHub)
├── ARCHITECTURE.md                     # System design and the *why* (consolidated)
├── CHANGELOG.md                       # Released-change log (Keep a Changelog; agent-maintained)
├── ROADMAP.md                         # Backlog (shipped work → CHANGELOG.md)
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

**Release commit** — the `VERSION` bump is `chore(release): <version>`, made as the last commit before merge (see [the maintainer flow](#branching-and-pull-requests)). **In that same commit, promote the CHANGELOG**: rename `## [Unreleased]` to `## [<version>] - <YYYY-MM-DD>` and open a fresh empty `## [Unreleased]` above it, so the [release job](#git-tags--releases) finds a matching section to publish. Bumping `VERSION` while the entries still sit under `## [Unreleased]` is the classic slip — the release job now **fails closed** on a missing `## [<version>]` section rather than shipping an empty release, so forgetting breaks the release loudly instead of silently.

## When to update what

**ROADMAP.md** — a real idea worth keeping but not doing now → add it. A decision we made and are sticking with → don't add it (commit message is enough). A known shortcoming we've accepted as a trade-off → add it, so it doesn't get forgotten. When a roadmap item ships, delete its bullet and add a terse [CHANGELOG.md](CHANGELOG.md) entry in the same commit.

**CHANGELOG.md** — every user-facing change that ships under a `VERSION` bump → a terse entry under that version ([Keep a Changelog](https://keepachangelog.com/); agent-maintained, rationale stays in the commit). Doc/CI/contributor-only changes that don't bump usually don't need one.

**README.md** — anything that changes how a user installs, runs, or thinks about konrad. A new subcommand or flag. A new external dependency (e.g. a tool the user has to install on the host).

**CLAUDE.md** — this is the repo-level instructions file, loaded by Claude Code (and any other agent) working *on* konrad. Update when there's a new tool/file/directory the agent should know about, a new convention or constraint the agent should follow, or a structural change (config layering, state tiers, image stages). The runtime konrad agent's *environment manifest* lives separately at `image/opencode/instructions/environment.md` (baked into the image, loaded by opencode at runtime via the layered `instructions` globs — it's the baked layer's `instructions/` entry); update that file when shipped tools, Python libraries, or the filesystem layout change.

Keep all three tight — every byte competes with task context inside the model's window.

## Code of conduct

Be kind, be specific, assume good faith. We follow the [Contributor Covenant v2.1](https://www.contributor-covenant.org/version/2/1/code_of_conduct/). Report unacceptable behavior to the maintainer via private channel (email in the git log).

## Backlog and known gaps

See [ROADMAP.md](ROADMAP.md) for the full backlog and how items are prioritized — including the known shortcomings (Windows support, automated tests, multi-language UI) tracked there as accepted trade-offs. The user-facing [README Status section](README.md#status) summarises what to expect today.
