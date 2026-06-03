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

By submitting a PR you agree your contributions are licensed under **AGPL-3.0-only** (see [LICENSE](LICENSE)). Konrad is strong-copyleft on purpose — anyone running it (including over a network) has to publish their source. If that's incompatible with your situation, please don't submit.

No CLA, no DCO. The license terms attach automatically.

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

The repo ships a Dev Container at `.devcontainer/` — "Reopen in Container" in VS Code gives you a portable edit-and-lint environment (shellcheck, hadolint, actionlint, jq, git, ripgrep, the Claude Code extension preinstalled). It also mounts the host's rootless Podman socket, so `konrad-dev --rebuild`, `konrad-dev --shell`, and most of `./scripts/smoke-test.sh konrad:local` run **from inside the container** against the host's Podman daemon — no privileged Podman-in-container needed. **Linux prerequisite:** enable the socket once on the host with `systemctl --user enable --now podman.socket`, or the container won't start. In this mode the daemon resolves bind-mount paths on the host, so konrad's host-home mounts (logs, config layers) are skipped and the smoke test's org-layer section is unavailable; **macOS uses a different (VM) socket path and isn't wired up yet** (see [ROADMAP.md](ROADMAP.md)).

## Local development loop

```sh
# Edit files...
konrad-dev --rebuild                                      # builds konrad:local
konrad-dev --shell                                        # exercise the dev image
shellcheck bin/konrad image/entrypoint.sh scripts/*.sh    # lint
./scripts/smoke-test.sh konrad:local                      # smoke
```

`konrad-dev` defaults to the `konrad:local` image (the one its own `rebuild` writes), so you exercise your dev build with no env var fiddling. The stable `konrad` next to it on `PATH` keeps pointing at `konrad:latest` — your day-to-day agent work is unaffected by whatever you're testing.

There's no traditional unit-test suite. The validation gates are:

- `bash -n <script>` — parse check
- `shellcheck <script>` — static analysis, should stay clean
- `./scripts/build-image.sh` — does the image build?
- `./scripts/smoke-test.sh konrad:local` — does the image have the right binaries / Python deps / baked content, and does the docling round-trip work? CI runs this same script.
- A live poke: `cd /tmp/konrad-test && konrad-dev --version` then `konrad-dev --shell` to look around. Dump the full build manifest with `podman run --rm --entrypoint cat konrad:local /etc/konrad/build-manifest.json | jq .`.

**Always smoke-test locally before pushing changes that touch `image/`, `scripts/smoke-test.sh`, or `image/build-manifest.sh`.** CI catches the bug eventually but at a ~10 min round-trip cost per iteration vs. ~5.5 min locally (rebuild + smoke).

## Branching and pull requests

Trunk-based: `main` is always deployable — what's at `ghcr.io/jlbauss/konrad:latest` mirrors `main`'s current state. The primary repo is **GitLab** (`gitlab.git.nrw/jbauss2/konrad`, public). The GitHub mirror is a **private CI execution surface only** — it exists because gitlab.git.nrw's shared runners can't run the privileged Podman build (see [docs/design/design-decisions.md](docs/design/design-decisions.md)). You never need a GitHub account to contribute.

**Maintainer** (direct repo access) — trunk-based via the git CLI, no MR ceremony:

1. Branch off main: `git checkout -b feat/short-name`
2. Commit (bump `VERSION` — see below)
3. `git checkout main && git merge --ff-only feat/short-name && git push origin main`

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

Pre-1.0 rules (where we are today):

- `VERSION` holds `0.X` (no third number)
- Bump `X` for any functional change to `image/`, `bin/konrad`, baked skills, or `image/konrad-defaults/`
- Doc-only, CI-only, ROADMAP-only changes don't bump

The full design — including post-1.0 semver semantics, the tag scheme on the registry, when 1.0 happens, and when git tags / GitHub Releases get cut — lives in [docs/design/versioning-and-releases.md](docs/design/versioning-and-releases.md).

## Repo layout — what goes where

```
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
├── .github/workflows/build-image.yml  # CI: build → smoke → publish (multi-arch amd64 + arm64)
├── .gitlab-ci.yml                     # Lock-resolver bot (source of truth; mirrors to GitHub)
├── docs/design/                       # Long-form design rationale (the "why" notes)
├── ROADMAP.md                         # Backlog tiers + dated `## Implemented` changelog
├── CLAUDE.md                          # Repo instructions for agents working ON konrad
├── NOTICE                             # Upstream attribution
├── .devcontainer/                     # VS Code Dev Container for working ON konrad (Claude Code preinstalled)
└── devcontainer/                      # Experimental: Dev Container as a way to USE konrad (see ROADMAP)
```

If a change touches multiple concerns, prefer separate commits per concern. The git log is the project's primary design history — keep it useful.

## Commit style

Conventional commit subject, no scope prefix unless useful:

```
short imperative subject in lowercase

body explaining *why*, wrapping at ~72 cols. include surprising
constraints or non-obvious tradeoffs. don't re-state what the diff
shows.

Co-Authored-By: ...   (only when applicable)
```

Use multi-line bodies for any change that needed a design decision. The git log is the project's primary design history — keep it useful.

## When to update what

**ROADMAP.md** — a real idea worth keeping but not doing now → add it. A decision we made and are sticking with → don't add it (commit message is enough). A known shortcoming we've accepted as a trade-off → add it, so it doesn't get forgotten. When a Tier-N item ships, move it to `## Implemented` in the same commit, prefixed with the ISO date.

**README.md** — anything that changes how a user installs, runs, or thinks about konrad. A new subcommand or flag. A new external dependency (e.g. a tool the user has to install on the host).

**CLAUDE.md** — this is the repo-level instructions file, loaded by Claude Code (and any other agent) working *on* konrad. Update when there's a new tool/file/directory the agent should know about, a new convention or constraint the agent should follow, or a structural change (config layering, state tiers, image stages). The runtime konrad agent's *environment manifest* lives separately at `image/opencode/environment.md` (baked into the image, loaded by opencode at runtime via the `instructions` config key); update that file when shipped tools, Python libraries, or the filesystem layout change.

Keep all three tight — every byte competes with task context inside the model's window.

## Code of conduct

Be kind, be specific, assume good faith. We follow the [Contributor Covenant v2.1](https://www.contributor-covenant.org/version/2/1/code_of_conduct/). Report unacceptable behavior to the maintainer via private channel (email in the git log).

## Backlog and known gaps

See [ROADMAP.md](ROADMAP.md) for the full backlog and how items are prioritized — including the known shortcomings (Windows support, automated tests, multi-language UI) tracked there as accepted trade-offs. The user-facing [README Status section](README.md#status) summarises what to expect today.
