# Contributing to konrad

Thanks for your interest. Konrad is early-stage / alpha software — the runtime works, the daily-rebuild CI works, but the surface area is still moving and the docs lag the code in spots. Contributions of all sizes are welcome, especially the ones that surface gaps before more users do.

## Before you start

If you're proposing something larger than a typo fix, **open an issue first** to discuss. A short "I'd like to add X — does that fit?" conversation saves rework when the maintainer would have steered you elsewhere. For tiny things (typos, broken links, obvious one-line bugs), skip straight to a PR.

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

```sh
# Fork on GitHub, then:
git clone git@github.com:<your-username>/konrad.git
cd konrad

./scripts/install.sh              # symlinks bin/konrad into ~/.local/bin
konrad update                     # pulls the current :latest from ghcr.io
                                  # (until the package is public you'll need
                                  #  a PAT — see the README's Install section)

konrad rebuild                    # builds konrad:local from your checkout
./scripts/smoke-test.sh konrad:local
```

You need:
- Podman (Linux/macOS host; Docker is on the roadmap but not supported yet)
- `~/.local/bin` on your `$PATH` (the installer warns if it isn't)

The repo ships a Dev Container at `.devcontainer/` — "Reopen in Container" in VS Code gives you a portable edit-and-lint environment (shellcheck, jq, git, ripgrep, the Claude Code extension preinstalled). Building and running the konrad image itself stays on the host, since Podman-in-container would need privileged mode.

## Local development loop

```sh
# Edit files...
konrad rebuild                                            # builds konrad:local
KONRAD_IMAGE=konrad:local konrad shell                    # exercise the dev image
shellcheck bin/konrad image/entrypoint.sh scripts/*.sh    # lint
./scripts/smoke-test.sh konrad:local                      # smoke
```

`konrad rebuild` writes to `konrad:local` so it can't accidentally clobber the published `konrad:latest` you pulled with `konrad update`. Set `KONRAD_IMAGE=konrad:local` to run the dev image; default `konrad` always runs `konrad:latest`.

There's no traditional unit-test suite. The validation gates are:

- `bash -n <script>` — parse check
- `shellcheck <script>` — static analysis, should stay clean
- `./scripts/build-image.sh` — does the image build?
- `./scripts/smoke-test.sh konrad:local` — does the image have the right binaries / Python deps / baked content, and does the docling round-trip work? CI runs this same script.
- A live poke: `cd /tmp/konrad-test && konrad version --manifest` then `KONRAD_IMAGE=konrad:local konrad shell` to look around.

**Always smoke-test locally before pushing changes that touch `image/`, `scripts/smoke-test.sh`, or `image/build-manifest.sh`.** CI catches the bug eventually but at a ~10 min round-trip cost per iteration vs. ~5.5 min locally (rebuild + smoke).

## Branching and pull requests

Trunk-based with PR-gated merges. `main` is always deployable — what's at `ghcr.io/jlbauss/konrad:latest` mirrors `main`'s current state.

Workflow for maintainer / collaborators:

1. Branch off main: `git checkout -b feat/short-name`
2. Commit your changes (and bump `VERSION` — see below)
3. Push the branch and open a PR on GitHub
4. CI builds the PR image and publishes it as `ghcr.io/jlbauss/konrad:pr-<num>`
5. Pull and test interactively:
   ```sh
   podman pull ghcr.io/jlbauss/konrad:pr-<num>
   KONRAD_IMAGE=ghcr.io/jlbauss/konrad:pr-<num> konrad shell
   ```
6. Merge when smoke is green and the PR image works
7. Main pipeline runs and publishes under the real tags (`:latest`, `:0.X.YYYY-MM-DD`, etc.)

Workflow for fork-based contributors:

1. Fork on GitHub, push your branch to your fork
2. Open a PR against `jlbauss/konrad:main`
3. CI runs build + smoke against your branch. **Publish to `:pr-<num>` is skipped from forks** — GitHub doesn't grant fork CI write access to the upstream registry. Smoke passing is the primary signal that your change is sound.
4. If the maintainer wants to test the PR image, they'll push your branch up to the upstream repo as `pr/<num>` to trigger a registry-publishing run

Branch naming: `feat/<short>`, `fix/<short>`, `docs/<short>`, `chore/<short>`. Keep the slug short — the descriptive bit lives in the PR title.

## Versioning

The `VERSION` file at the repo root drives all image tagging. **Bump it in the same PR as your change.** Reviewer checks the bump matches the change's semver impact.

Pre-1.0 rules (where we are today):

- `VERSION` holds `0.X` (no third number)
- Bump `X` for any functional change to `image/`, `bin/konrad`, baked skills, or `image/konrad-defaults/`
- Doc-only, CI-only, ROADMAP-only changes don't bump

The full design — including post-1.0 semver semantics, the tag scheme on the registry, when 1.0 happens, and when git tags / GitHub Releases get cut — lives in [docs/design/versioning-and-releases.md](docs/design/versioning-and-releases.md).

## What goes where

| Concern | Lives in |
| --- | --- |
| The container artifact | `image/` (Dockerfile + bundled `opencode/` config + fonts) |
| The host-side CLI | `bin/konrad` |
| Install / build helpers | `scripts/` |
| Container CI (build + smoke + publish) | `.github/workflows/build-image.yml` |
| Design rationale + dated changelog | `docs/design/` + ROADMAP `## Implemented` |
| VS Code Dev Container for working **on** konrad (Claude Code preinstalled) | `.devcontainer/` |
| Roadmap and idea backlog | `ROADMAP.md` |
| Upstream attribution | `NOTICE` |

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

**CLAUDE.md** — this is the repo-level instructions file, loaded by Claude Code (and any other agent) working *on* konrad. Update when there's a new tool/file/directory the agent should know about, a new convention or constraint the agent should follow, or a structural change (config layering, state tiers, image stages). Konrad's *own* model instructions live separately at `image/konrad-defaults/instructions.md` (baked into the image, loaded by opencode at runtime).

Keep all three tight — every byte competes with task context inside the model's window.

## Code of conduct

Be kind, be specific, assume good faith. We follow the [Contributor Covenant v2.1](https://www.contributor-covenant.org/version/2/1/code_of_conduct/). Report unacceptable behavior to the maintainer via private channel (email in the git log).

## Out of scope right now

- Windows host support. Podman with `--userns=keep-id` is Linux/macOS only. Docker support is on the roadmap (Tier 2).
- A traditional unit-test suite. The smoke test gates publish; "image actually does what users need" is currently exercised by hand.
- Multi-language UI. English-only today; multi-language support is on the roadmap (Tier 1).

See [ROADMAP.md](ROADMAP.md) for the full backlog and how items are prioritized.
