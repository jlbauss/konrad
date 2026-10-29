# Contributing to konrad

Thanks for your interest. konrad is a personal tool, shared as it is ([README → Status](README.md#status)): one person maintains it for their own use, so issues and merge requests are welcome but come with no promise of review or response time. Small, focused changes stand the best chance.

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

By submitting a merge request you agree your contributions are licensed under **AGPL-3.0-or-later** (see [LICENSE](LICENSE)). konrad is strong-copyleft on purpose — anyone running it (including over a network) has to publish their source. If that's incompatible with your situation, please don't submit.

No CLA, no DCO. The license terms attach automatically.

Licensing follows the [REUSE](https://reuse.software) spec, verified by `reuse lint`. **Add an SPDX header to every new or edited source file** — two comment lines near the top:

```text
# SPDX-FileCopyrightText: 2026 Your Name
# SPDX-License-Identifier: AGPL-3.0-or-later
```

Vendored third-party files keep their *upstream* `SPDX-FileCopyrightText` + license instead. Files that can't carry a comment (fonts, other binaries) and the project default are handled by globs in [`REUSE.toml`](REUSE.toml); when you introduce a new license, add its text under `LICENSES/` (`reuse download <SPDX-ID>`). Keep `reuse lint` green — CI enforces it.

## First-time setup

konrad keeps the user CLI and the dev CLI as separate binaries on `PATH`, so you can hack on the source without disturbing your day-to-day stable `konrad`:

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

- A container engine — **Podman** on Linux (and inside `konrad code`), or Apple's **`container`** on Apple-Silicon macOS 26+. `konrad-dev rebuild` builds on whichever it runs on: Podman via buildah, apple/container via `container build` (straight into its own store — no Podman needed on the Mac). Docker is on the roadmap but not supported yet.
- `~/.local/bin` on your `$PATH`

- **uv** and **node** (with `npx`) for `scripts/check.sh`, which fetches the lint tools at pinned versions on first use

That's the whole host toolchain; there's deliberately no dev container (why: [ARCHITECTURE → konrad code](ARCHITECTURE.md#konrad-code)). In VS Code, accept the workspace's recommended extensions (markdownlint and shellcheck, both bundling their linter) — [.vscode/settings.json](.vscode/settings.json) applies the markdownlint fixes on save. For a shell with the agent's exact toolset and a nested Podman, nothing installed on your host, run `konrad code --shell https://gitlab.git.nrw/jbauss2/konrad`: the same sealed box an agent works in, with its own clone.

**Agents work in `konrad code`, not in your checkout.** Launch one with `konrad code https://gitlab.git.nrw/jbauss2/konrad`: a disposable container with its own clone, its own rootless Podman (so it builds, smoke-tests and self-tests the image itself) and open internet, but no host mounts and a sealed LAN; it hands work back only as a merge request ([ARCHITECTURE → konrad code](ARCHITECTURE.md#konrad-code)). The agent-side rules live in [CLAUDE.md](CLAUDE.md).

## Local development loop

```sh
# Edit files...
konrad-dev rebuild                                      # builds konrad:local
konrad-dev shell                                        # exercise the dev image
./scripts/check.sh                                        # static gates (what CI runs)
./scripts/smoke-test.sh konrad:local                      # smoke (image artifact)
./scripts/selftest.sh                                     # end-to-end (image + a real run)
```

`konrad-dev` defaults to the `konrad:local` image (the one its own `rebuild` writes), so you exercise your dev build with no env var fiddling. The stable `konrad` next to it on `PATH` keeps pointing at `konrad:latest` — your day-to-day agent work is unaffected by whatever you're testing.

The validation gates are:

- `./scripts/check.sh` — the static gates and the unit tests in one command: `bash -n`, shellcheck, `reuse lint`, markdownlint, actionlint, hadolint, and `tests`, the [bats](https://github.com/bats-core/bats-core) suites in [tests/](tests/) (`bin/konrad`'s host-side functions under the script's own `set -euo pipefail`, and `merge-config.js`'s layering contract), each tool at a version pinned in the script; `tests` also needs `jq`. GitLab CI runs the same script on every MR, so a green local run is a green pipeline. `./scripts/check.sh <gate>…` runs a subset.
- `./scripts/build-image.sh` — does the image build?
- `./scripts/test-autoupdate.sh` — the update rehearsal: installs the previous release's CLI under a throwaway `HOME`, then runs a real `konrad update` and background refresh against a local registry holding `konrad:local` and this checkout's files instead of the forge. Run it after `konrad-dev rebuild` for any change to `bin/konrad`, `scripts/install.sh` or the update path. Podman only (the nested engine in `konrad code` is fine).
- `./scripts/ab-test.sh --a <image> --b <image> <task>…` — for a change whose effect only shows in what the agent does (a skill swapped for an upstream one, a prompt edit): runs each task in [tests/ab/](tests/ab/) several times per image through `konrad-dev run` with a real model, A and B interleaved, grades every run with the task's `grade.py`, and writes a report of score, cost, time, steps and skills loaded under `.skill-eval/`. The runs get a `HOME` of their own: copies of your org and user layers (so your providers work) under a layer that allows `rm -rf`, whose `ask` a `konrad run` can only reject, which ends the run. A task is a `prompt.md`, an `input/` dir and a grader that prints which checks passed; the tasks cover Word, Excel and PowerPoint files, emails, PDFs (reading a table, writing a letter), a receipt photo, a CSV analysis with a chart, a long document, a bug fix and sorting files. Build the baseline first (`konrad-dev rebuild` on `origin/main`, then `podman tag konrad:local konrad:ab-a`), then the change. It needs a provider key; in unattended runs the capped one ([below](#a-real-model-in-unattended-runs)), with `anthropic/claude-haiku-5-5` at `--variant low` (the default) as a stand-in for the recommended local model. How fair a stand-in it is was measured once, against Qwen3.8 27B via OpenRouter on all the tasks ([report](tests/ab/reports/2026-10-29-models/)): 27B passed the graders' checks as often, but the blind judge preferred Haiku in 7 of 17 tasks and 27B in one, and 27B took six times as long, answered German input in English and once leaked a tool-call tag into its reply. So Haiku is a kind stand-in, hiding the polish, speed and language problems of a mid-size open-weights model: read a Haiku result as an upper bound, and check a change aimed at smaller models (instruction wording, language, "leave X out" rules) on one as well. For a skill change Haiku is no stand-in at all: unprompted it loads a skill in 0–2 of 10 runs, while 27B loads the matching one every time, and `--prompt-suffix` measures a skill's content in a setting no user is in ([ROADMAP → Lived with](ROADMAP.md#lived-with)). A fast small model and a local runtime weren't measured; the maintainer closed the question there (2026-10-29). To compare two models instead, give both sides the same image and each its own model: `--a-model`, `--b-model`, and `--a-variant`/`--b-variant` for the effort (`''` is the model's default). Podman only.
- `./scripts/ab-judge.sh blind|report <results>` — the blind judge on top: how good the deliverables are, beyond the graders' pass/fail checks. `blind` turns each pair of runs into two packets (X and Y swapped, under random ids) holding the task, its input and both deliverables as page renders, text and speaker notes (emails with their attachments, images, code), plus a list of the files each run left, and puts them in batches of ten, one task and one order per batch, each in a folder of its own with `JUDGE.md`. The agent session that ran the A/B hands each batch's folder to an [`ab-judge`](.claude/agents/ab-judge.md) subagent as the only path it gets: Sonnet, with only Read, Write and Glob, a start of about 17k tokens instead of a general-purpose subagent's 40k, which each judge pays again on every step and which made up more than half of what judging cost. Sonnet, not Opus: on the 2026-10-29 skills test Opus judges agreed with themselves more often (32 of 35 pairs) but cost about $0.20 a packet against Sonnet's $0.05. Each judge writes a `verdict.json` per packet without learning which side is which. The folder holding the batches can't be listed, so a judge's wildcard reaches only its own packets: in the first model comparison, four of 34 judges had read other packets' files through one, against the instruction not to. The list of batch folders, `judge-batches.txt`, sits beside the key in the results dir, so a judge that wanders up from its folder finds no other batch's name. `report` unblinds them, counts a pair for a side only when both orders agree, and writes `report/`: a dated `README.md` that reads like a short study (the answer and an overview first, then numbered sections: what was compared, how, results per task, limits), with side-by-side page images in `img/` only where one version won. Pick those pages yourself after reading the reasons, `--show <task>:<run>:<page>[,<page>]` per task, so each image shows what decided it, and name the sides (`--a-name Haiku --b-name "Qwen 27B"`) so the report doesn't speak of A and B. Commit it in the MR as `tests/ab/reports/<date>-<name>/` and link it from the description; GitLab and the GitHub mirror both display it, and it's public once merged ([the first one](tests/ab/reports/2026-10-28-office-skills/)). The judge found what the graders couldn't: in its first trial (2026-10-28) the deck without `powerpoint` won 10 of 10 pairs, on layout alone.
- `./scripts/smoke-test.sh konrad:local` — does the image have the right binaries / Python deps / baked content, and does the docling round-trip work? CI runs this same script. (Engine-agnostic and deliberately `bin/konrad`-free — CI runs it under Docker, and it validates the *image artifact*, not the host CLI.)
- `./scripts/selftest.sh` — the realistic end-to-end loop, and the right gate to hand an agent: it runs the smoke test, then drives a real `konrad run` *through `bin/konrad`* (uid mapping, workspace mount, config compose — the path a user actually takes) and asserts the agent answers. The **model comes from your own `~/.config/konrad` config** (override with `--model <slug>` / `KONRAD_SELFTEST_MODEL`, any provider; `--variant <effort>` / `KONRAD_SELFTEST_VARIANT` sets its reasoning effort); with no usable model/credential the model stage degrades to a SKIP, so a red result always means the *runtime* broke. One-time on your host: populate the shared `konrad-secrets` volume via `konrad-dev connect`. In `konrad code` and other unattended runs, use a capped test key instead ([below](#a-real-model-in-unattended-runs)). Not a CI gate.
- A live poke: `cd /tmp/konrad-test && konrad-dev --version` then `konrad-dev shell` to look around. Dump the full build manifest with `podman run --rm --entrypoint cat konrad:local /etc/konrad/build-manifest.json | jq .`.

**Always smoke-test locally before pushing changes that touch `image/`, `scripts/smoke-test.sh`, or `image/build-manifest.sh`.** CI catches the bug eventually but at a ~10 min round-trip cost per iteration vs. ~5.5 min locally (rebuild + smoke).

### A real model in unattended runs

An agent in `konrad code` runs the selftest's model stage when its session holds a provider key, and SKIPs it otherwise. Its box has open internet and the agent can read the key, so the key is made safe by what it can spend, not by being hidden ([ARCHITECTURE → konrad code](ARCHITECTURE.md#konrad-code)):

1. **Create a key just for this, with a hard spend limit**, never your everyday key. In the Anthropic Console, that's a workspace of its own (say `konrad-selftest`) with a low monthly spend limit, and an API key created inside that workspace: the limit belongs to the workspace, so a key in your Default workspace would share your normal budget. An OpenRouter key with a credit limit works the same way. Rotate it now and then.
2. **Connect it in each session that should use it.** Every `konrad code` session keeps its own nested volumes, so its own key store: the primary session, each parallel one (`s2`, …) and the `up` container. The key stays across restarts of that session. Pick the provider's API-key login (not a Pro/Max subscription login), and type the key only into that prompt, never into an agent's chat, whose transcript would keep it.
   - A terminal session: `konrad code --shell --session <name> https://gitlab.git.nrw/jbauss2/konrad` (the clone's session is `primary`), then `bin/konrad connect -p anthropic`.
   - The `up` container that serves sessions from the Claude app or claude.ai/code: from the host, find its `konrad-up-…` name with `podman ps --format '{{.Names}}'` (Linux) or `container ls` (macOS), then run the matching command below. A shell opened with `exec` doesn't inherit the entrypoint's `CONTAINERS_CONF_OVERRIDE`, and without it the key lands in the primary session's store.

   ```sh
   podman exec -it -u node -e CONTAINERS_CONF_OVERRIDE=/tmp/konrad-session-containers.conf -w /workspace/konrad <konrad-up-name> bin/konrad connect -p anthropic
   ```

   ```sh
   container exec -it -u node -e CONTAINERS_CONF_OVERRIDE=/tmp/konrad-session-containers.conf -w /workspace/konrad <konrad-up-name> bin/konrad connect -p anthropic
   ```

3. **Run the selftest with a cheap model at its lowest effort:** `./scripts/selftest.sh --model anthropic/claude-haiku-5-5 --variant low` after `konrad-dev rebuild` (add `--image konrad:latest` to test the released image instead). opencode lists a provider's models only once it's connected: `konrad-dev --profile selftest opencode models anthropic` shows them, and `--verbose` adds each model's variants.

## Branching and pull requests

Trunk-based: `main` is always deployable — what's at `ghcr.io/jlbauss/konrad:latest` mirrors `main`'s current state. The primary repo is **GitLab** (`gitlab.git.nrw/jbauss2/konrad`, public). The GitHub mirror is **public for discoverability, but CI-and-releases only** — it exists because gitlab.git.nrw's shared runners can't run the privileged Podman build (see [ARCHITECTURE.md](ARCHITECTURE.md)), and [mirror-release.yml](.github/workflows/mirror-release.yml) recreates each GitLab release there off the mirrored tag. Contributions happen on GitLab; you never need a GitHub account to contribute.

**Maintainer** (direct repo access) — every change lands through a **merge request**, whether you wrote it or an agent did; `main` is protected. The loop is **branch → develop → MR → merge**:

1. **Branch** off the current main: `git fetch origin && git checkout -b feat/short-name origin/main`
2. **Develop** and commit; `./scripts/check.sh` before pushing.
3. **Push and open the MR**: `git push -u origin feat/short-name -o merge_request.create -o merge_request.target=main -o merge_request.remove_source_branch`. The [MR template](.gitlab/merge_request_templates/Default.md) asks for summary, why, what was validated and the probes left for you. Leave `VERSION` and `CHANGELOG.md` alone: CI releases after the merge ([Release commit](#commit-style)).
4. **Merge** in the web UI once the pipeline is green. The project merges fast-forward only (linear history, one commit per concern, no squash); the locks bot moves `main` almost daily, so most MRs need GitLab's one-click **Rebase** first. The source branch is deleted on merge.

**Reviewing an agent's MR.** An agent in `konrad code` pushes its branch as a draft MR whose description is its write-up, including any probes only you can run. It writes those only where a slip would cross a security boundary or delete data, each with a baseline first ([CLAUDE.md → Working with the user](CLAUDE.md#working-with-the-user)); for anything else it says how you'd notice in normal use. **Read the diff before you run any of the branch's code on your host** — `git pull` + `./scripts/selftest.sh`, an installer run, even a `konrad-dev` launch executes the agent's code with your rights and no sandbox, which is exactly the deferred escape `konrad code` otherwise prevents. Then run the probes, ticking each one's checkbox in the MR description as it passes (GitLab records the tick in the MR's activity), mark the MR ready, and merge.

The image check for a change is the agent's own: it builds, smokes and self-tests the image in its `konrad code` box and reports that under *Validation run*. For a higher-risk change you can still get a CI-built `:pr-<num>` image (see *Testing a change as an image* below), but only by hand: the push mirror carries protected branches only, so push the branch to the GitHub repo yourself and open a PR there; merge on GitLab once it checks out.

**Collaborators** (have GitLab repo access) — the same loop: branch on the repo, push, and open a **GitLab MR**; `main` is protected, so the MR is the only way in. The maintainer merges it.

**External contributors** (the public) — everything happens on GitLab:

1. **Fork** the GitLab repo and branch off `main`.
2. Commit (follow the commit style below; leave `VERSION` and `CHANGELOG.md` alone) and push to your fork.
3. Open a **GitLab MR** against `main` — that's the review surface.
4. A fork MR gets human review automatically, but **no automatic image build**: the build runs on the GitHub mirror, which carries only the main repo's protected branches. When the change is worth exercising in a container, the maintainer builds your branch locally, or pushes it to the GitHub repo by hand and opens a PR there to produce a `:pr-<num>` image.
5. The maintainer merges on GitLab.

**Testing a change as an image** (`:pr-<num>`). PR builds go through the same build → smoke gate as `main` but publish *only* to `:pr-<num>` — never `:latest` or a release tag. Because the GHCR package is public, once a PR image exists anyone can pull and run it, no GitHub access needed:

```sh
podman pull ghcr.io/jlbauss/konrad:pr-<num>
KONRAD_IMAGE=ghcr.io/jlbauss/konrad:pr-<num> konrad shell
```

Branch naming: `feat/<short>`, `fix/<short>`, `docs/<short>`, `chore/<short>`. Keep the slug short — the descriptive bit lives in the MR title.

## Versioning

The `VERSION` file at the repo root drives all image tagging. **Only a release bumps it** ([Release commit](#commit-style)), never a feature MR, so parallel MRs don't collide on it.

`VERSION` holds `0.X.Y`, and the commit types since the last release pick the bump: **`X` (minor)**, resetting `Y` to 0, for a `feat` or a breaking change (`!` / `BREAKING CHANGE:`, any type — see [Commit style](#commit-style)); **`Y` (patch)** for a `fix` or `perf`. Any other type (docs, CI, ROADMAP, locks, tests, refactors) releases nothing.

There's no plan for 1.0: it would promise no breaking change without a major bump, and a personal tool doesn't make that promise ([README → Status](README.md#status)).

### Image tags

CI publishes each build to `ghcr.io/jlbauss/konrad` under several tags:

| Tag | Mutable? | Meaning |
|---|---|---|
| `:0.X` | rolling | newest passing build on the minor line — the **pin-a-line** handle: get patches, stop at the next `X`. |
| `:latest` | rolling | newest passing build overall — the **only tag the CLI reads** (`konrad update` pulls this) |
| `:<short-sha>` | **immutable** | the one per-build handle that never moves — maps 1:1 to a commit. Use it for rollback, bisecting, and `scripts/layer-diff.sh`. |
| `:pr-<num>` | per-PR | reviewer test image; never touches `:latest` or a line tag |

There is deliberately **no version- or date-derived image tag**. `VERSION` drives the *CLI*, not image content — a CLI-only patch bumps `VERSION` without firing an image rebuild ([the `image/**` paths filter](.github/workflows/build-image.yml)) — so an image-side `:0.X.Y` would promise a precision the build can't keep, and a `:0.X.Y-DATE` tag isn't immutable (two builds the same day overwrite it). The honest immutable handle is `:<short-sha>`; `konrad --version` prints it as the image identity. To pin an exact image, pin the SHA.

### Git tags & releases

Releases are cut on **GitLab** — the authoritative record — and mirrored to GitHub automatically: [mirror-release.yml](.github/workflows/mirror-release.yml) fires on each mirrored `v*` tag and recreates the release from the same CHANGELOG section (its `workflow_dispatch` backfills any tag that's missing one). Tags are **`vX.Y.Z`** (`v`-prefixed). Nothing is done by hand: after every merge to main, the `release-mr` job in [`.gitlab-ci.yml`](.gitlab-ci.yml) runs [scripts/release.sh](scripts/release.sh), which picks the [bump](#versioning) from the commits since the last `VERSION` change and has [git-cliff](https://git-cliff.org) ([cliff.toml](cliff.toml)) write their [CHANGELOG.md](CHANGELOG.md) section, and lands that as the [release commit](#commit-style) through an auto-merging MR. When it merges, the `release` job cuts the `v<VERSION>` tag and a GitLab Release with that section as its notes; it fails closed if `## [<VERSION>]` is missing.

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
│   │   └── skills/                    # konrad's own skills (pdf, image-editing, frontend-design, do-it-manually, grill-me, write-a-skill, quality-assurance); upstream ones come from locks/skills.lock
│   └── fonts/konrad/                  # → /usr/local/share/fonts/konrad/ (seven OFL families)
├── scripts/
│   ├── build-image.sh                 # Local build (KONRAD_VERSION + GIT_SHA build args)
│   ├── check.sh                       # Static gates (lint, REUSE) — CI runs this same script
│   ├── smoke-test.sh                  # Smoke gate — CI runs this same script
│   ├── test-autoupdate.sh             # Update rehearsal: previous release → this checkout, local registry
│   ├── ab-judge.sh                    # blind judging of an ab-test.sh run by an agent session's subagents
│   ├── ab-test.sh                     # A/B two images, or two models, on the tasks in tests/ab/
│   ├── forge-api.sh                   # GitLab API reads (MRs, pipelines, logs) with the session's token
│   ├── release.sh                     # Next VERSION + its CHANGELOG section (CI runs it after each merge)
│   ├── install.sh              # curl|sh installer — fetches the CLI standalone, bakes VERSION in
│   └── fetch-fonts.sh                 # One-shot — pulls fonts from upstream when bumping versions
├── examples/org-package/              # Git-native org-layer example repo (referenced from README)
├── .github/workflows/build-image.yml  # CI: build → smoke → publish (multi-arch amd64 + arm64)
├── .gitlab-ci.yml                     # Static gates, lock-resolver bot, release bot and job (source of truth; mirrors to GitHub)
├── .gitlab/merge_request_templates/   # MR description template
├── ARCHITECTURE.md                     # System design and the *why* (consolidated)
├── CHANGELOG.md                       # Released-change log (Keep a Changelog; written by CI)
├── cliff.toml                         # git-cliff config: how a release's commits become its CHANGELOG section
├── ROADMAP.md                         # Backlog (shipped work → CHANGELOG.md)
├── CLAUDE.md                          # Repo instructions for agents working ON konrad
├── REUSE.toml                         # Per-file copyright/license by glob (REUSE spec)
├── LICENSES/                          # SPDX license texts (REUSE)
└── .vscode/                           # Recommended extensions + markdownlint-on-save (the rest of .vscode/ is ignored)
```

If a change touches multiple concerns, prefer separate commits per concern. The git log is the project's primary design history — keep it useful.

## Commit style

[Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/), applied fully — by discipline, checked at review. CI reads them: the types pick the [version bump](#versioning), and every `feat`, `fix` and `perf` subject becomes a [CHANGELOG.md](CHANGELOG.md) entry, word for word.

```text
type(scope)?: imperative, lowercase subject, no trailing period

Body — expected for anything that needed a design decision: explain *why*
(surprising constraints, non-obvious tradeoffs), wrapped at ~72 cols. Don't
restate the diff; the git log is the project's primary design history.

BREAKING CHANGE: <what breaks + how to migrate>   (footer, when applicable)
Co-Authored-By: ...                               (when applicable)
```

**Types** — `feat` (new capability), `fix` (bug fix), `docs`, `refactor` (no behaviour change), `perf`, `test`, `build` (build system / deps), `ci`, `style` (formatting only), `chore` (housekeeping — locks, etc.), `revert`.

**Scope** — optional; use one where it adds signal, from: `cli`, `image`, `config`, `skills`, `ci`, `locks`, `roadmap`, `release`.

**Breaking changes** — mark with `!` after the type/scope (e.g. `feat!:`) and/or a `BREAKING CHANGE:` footer. It makes the next release at least a **minor** bump — see [Versioning](#versioning).

**Subjects are changelog entries** — so write a `feat`, `fix` or `perf` subject for the user who reads the release: what they can now do or what no longer goes wrong (`fix(cli): resume an apple/container pull that the registry cuts off`), not the function you changed. A fix users never saw (to a test, a script, an unreleased feature) is `test`, `chore` or `refactor`, or folds into the commit it fixes.

**Release commit** — CI makes it: `chore(release): <version>`, bumping `VERSION` and adding `## [<version>] - <YYYY-MM-DD>` to CHANGELOG.md, through an auto-merging MR after every merge that has something to release ([Git tags & releases](#git-tags--releases)). Feature MRs never touch either file. A release that needs more than the subjects say (a migration note, say) gets it from a maintainer edit to the release MR before it merges, or to CHANGELOG.md after.

## When to update what

**ROADMAP.md** — at most ten items: what automates the maintainer's checks, what keeps konrad safe and working for its own use, and what makes it smaller. An item comes in only when the maintainer wants it, and replaces an old one; an idea that doesn't make the cut lives in the commit or MR that raised it. A decision we made and are sticking with doesn't go there either (the commit message is enough). When an item ships, delete its bullet in the same commit. Outside the cap, **Upstream workarounds and limitations** tracks every upstream bug konrad works around or lives with: a commit that adds a workaround, or documents a limitation instead, adds its bullet there (upstream link, what to check, what to remove), and the commit that removes it deletes the bullet.

**CHANGELOG.md** — written by CI in the release commit, one entry per `feat`, `fix` and `perf` subject since the last release ([Keep a Changelog](https://keepachangelog.com/); rationale stays in the commit). Feature MRs leave it alone.

**README.md** — anything that changes how a user installs, runs, or thinks about konrad. A new subcommand or flag. A new external dependency (e.g. a tool the user has to install on the host).

**CLAUDE.md** — this is the repo-level instructions file, loaded by Claude Code (and any other agent) working *on* konrad. Update when there's a new tool/file/directory the agent should know about, a new convention or constraint the agent should follow, or a structural change (config layering, state tiers, image stages). The runtime konrad agent's *environment manifest* lives separately at `image/opencode/instructions/environment.md` (baked into the image, loaded by opencode at runtime via the layered `instructions` globs — it's the baked layer's `instructions/` entry); update that file when shipped tools, Python libraries, or the filesystem layout change.

Keep all three tight — every byte competes with task context inside the model's window.

## Code of conduct

Be kind, be specific, assume good faith. We follow the [Contributor Covenant v2.1](https://www.contributor-covenant.org/version/2/1/code_of_conduct/). Report unacceptable behavior to the maintainer via private channel (email in the git log).

## Backlog and known gaps

See [ROADMAP.md](ROADMAP.md) for the short list of planned work. Known shortcomings (no Windows, no Docker, rough edges with local models) are listed in the user-facing [README Status section](README.md#status) and aren't planned.
