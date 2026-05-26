# konrad

A CLI wrapper around [opencode](https://github.com/sst/opencode) that runs it inside a sandboxed Podman container preloaded with a curated tool set and tuned instructions. Aimed at making locally hosted agent models genuinely useful out of the box.

Status: **early / experimental**. The "safe" half of the original `safe-cowork` name (egress firewall, permission ACLs) is not yet implemented — see [ROADMAP.md](ROADMAP.md).

## What konrad gives you

- **A `konrad` CLI** you run from any folder on the host. It spins up the container with that folder mounted as the workspace, then drops you straight into opencode.
- **A Debian image** with a curated tool set (ripgrep, fd, jq, gh, pandoc, poppler-utils, plus Python 3 + uv with a system venv) so the agent doesn't have to install its own toolchain. Heavier tooling for specific skills lands as those skills are rebuilt.
- **opencode prewired** to talk to LM Studio (default), Ollama, or llama.cpp on the host — zero configuration on first run.
- **A layered config system** that lets you add any opencode-supported provider (Anthropic, OpenAI, OpenRouter, Gemini, …) via a tiny override file, without losing konrad's defaults.
- **A planning contract** baked into Konrad's agent prompt ([image/opencode/agents/konrad.md](image/opencode/agents/konrad.md)): a single `.agent/task.md` file for any task with side effects (understanding, plan, success criteria, decisions, outcome), and aggressive use of opencode's `todowrite` tool for live progress visibility. See [docs/design/task-md-and-todowrite.md](docs/design/task-md-and-todowrite.md) for the rationale.
- **A curated skill set.** Skills are loaded via opencode's `skill` tool from `~/.config/opencode/skills/`. The image ships with `do-it-manually` (structured-but-irregular data extraction), `spreadsheets` (xlsx/csv CRUD), `pdf` (extract / edit / annotate / fill / generate), and `quality-assurance` (the cross-skill verification cycle every producer invokes before reporting — visual or language). More on the way — see [ROADMAP.md](ROADMAP.md).
- **A curated font palette.** Seven SIL OFL families baked into the image (Inter, Source Serif 4, Fraunces, JetBrains Mono, EB Garamond, IBM Plex Sans, Atkinson Hyperlegible) plus Debian's Noto core for broad non-Latin script coverage (Arabic, Devanagari, Cyrillic, Greek, Hebrew, Thai, …). Generated PDFs / slides / typeset docs look intentional out of the box. Drop your own `.ttf` / `.otf` into `~/.config/konrad/fonts/` to extend. Catalogue at [image/opencode/skills/pdf/references/fonts.md](image/opencode/skills/pdf/references/fonts.md).

## Requirements

- **[Podman](https://podman.io/)** — Docker support is on the backlog. The image is run with `--userns=keep-id`, which is Podman-specific.
- **A model provider.** konrad ships pre-wired for three local engines:
  - **[LM Studio](https://lmstudio.ai/)** on `localhost:1234`, or
  - **[Ollama](https://ollama.com/)** on `localhost:11434`, or
  - **[llama.cpp](https://github.com/ggerganov/llama.cpp) server** on `localhost:8080`.

  konrad pre-wires each provider's endpoint but ships with **no models declared**. Declare the model(s) you've loaded in `~/.config/konrad/opencode.jsonc` — see [Configuration](#configuration) for recipes. (Auto-discovery used to live here but added meaningful startup cost; an inline replacement is on the roadmap.)

  For API providers (Anthropic, OpenAI, OpenRouter, etc.), also see [Configuration](#configuration).

- **Recommended model class.** konrad's skills and base instructions are tuned for a specifc class of models **30B-class open weight models** with extraordinary agentic capabilities — specifically [`qwen/qwen3.6-27b`](https://lmstudio.ai/models/qwen/qwen3.6-27b) is what we test against. Stronger models are beneficial. Requirements for models:
  - Native Vision Capability
  - Context Window recommended >= 256k Tokens
  - At least as strong as Qwen3.6 27B in the [Agentic Index by Artificial Analysis](https://artificialanalysis.ai/models/capabilities/agentic)
  
  as of May 20, 2026, the following models fulfill the requirements:

  - Open Weights
    - Qwen3.6 27B
    - Kimi K2.6
  - Proprietary
    - Claude Sonnet/Opus >= 4.6
    - GPT >= 5.4
    - Gemini 3.5 Flash

## Install

One-liner, no clone needed:

```sh
curl -fsSL https://gitlab.git.nrw/jbauss2/konrad/-/raw/main/scripts/install-remote.sh | sh
```

This drops `konrad` into `~/.local/bin/` (override with `KONRAD_INSTALL_DIR=…`), pre-pulls the container image (skippable with `KONRAD_NO_PULL=1`), and warns if you need to install podman or fix your `PATH`. Re-run any time to upgrade in place.

The first `konrad` run also auto-pulls if the image isn't already
present, so the explicit pre-pull is optional. If the registry is
unreachable, konrad falls back to a local build — substantially
slower, since it recompiles every layer and re-fetches model weights.

Working on konrad itself? See [CONTRIBUTING.md](CONTRIBUTING.md) — it walks you through cloning the repo and installing a parallel `konrad-dev` CLI that tracks your checkout (the stable `konrad` next to it stays untouched).

## Use

```sh
cd ~/wherever-you-keep-the-files-the-agent-will-touch
konrad
```

That's the whole UX: the current directory is mounted at `/workspace` inside the container, opencode starts pointing at LM Studio (or whatever you've configured), and you go.

### Flags

| Flag                     | What it does                                                            |
| ------------------------ | ----------------------------------------------------------------------- |
| _(none)_                 | Default. Runs opencode against the current directory.                   |
| `-s`, `--shell`          | Open a bash shell in the container instead of opencode.                 |
| `-v`, `--verbose`        | Per-phase timestamps + verbose opencode logs. Useful for chasing slow startup. |
| `--version`              | Print CLI version + image tag/digest/revision.                          |
| `--update`               | Pull the latest image from `ghcr.io/jlbauss/konrad:latest` and refresh the CLI script itself. |
| `--reset`                | Wipe shared volumes + log dir. Prompts `[y/N]`; affects all workspaces. |
| `--uninstall`            | Remove the CLI binary + the image. Prompts `[y/N]`. Leaves user config, shared volumes, and log dir alone — use `--reset` first if you want those gone too. |
| `-h`, `--help`           | Show usage.                                                             |

Short flags bundle (`konrad -sv` is `konrad -s -v`).

Working on konrad itself? `konrad-dev` is the contributor binary — same flags, except `--rebuild` replaces `--update` (it builds `konrad:local` from your checkout rather than pulling). See [CONTRIBUTING.md](CONTRIBUTING.md).

### Occasional maintenance (one-liners)

Operations rare enough that the CLI doesn't ship a verb for them:

| Goal                                 | Command                                                                                       |
| ------------------------------------ | --------------------------------------------------------------------------------------------- |
| Edit your user override              | `$EDITOR ~/.config/konrad/opencode.jsonc`                                                     |
| Start from the baked default         | `podman run --rm --entrypoint cat ghcr.io/jlbauss/konrad:latest /etc/konrad/opencode-defaults.jsonc > ~/.config/konrad/opencode.jsonc` |
| Diff your override vs. baked default | `diff -u <(podman run --rm --entrypoint cat ghcr.io/jlbauss/konrad:latest /etc/konrad/opencode-defaults.jsonc) ~/.config/konrad/opencode.jsonc` |
| Dump the build manifest              | `podman run --rm --entrypoint cat ghcr.io/jlbauss/konrad:latest /etc/konrad/build-manifest.json \| jq .` |
| Clear just the log dir               | `rm -rf ~/.local/state/konrad/log/`                                                           |
| Nuclear reset                        | `konrad --reset` (wipes log dir + all shared volumes; prompts `[y/N]`)                        |
| Full uninstall                       | `konrad --reset` → `konrad-dev --uninstall` (if installed) → `konrad --uninstall` → optionally `rm -rf ~/.config/konrad/` |

## Configuration

konrad composes opencode's runtime config from up to three layers at container start. **You only override what you want to change**; everything else stays inherited.

```
Layer 1 — Baked defaults     /etc/konrad/opencode-defaults.jsonc   (in the image)
Layer 2 — Your overrides     ~/.config/konrad/                     (on the host)
Layer 3 — Per-project        <workspace>/.opencode/opencode.json   (opencode-native)
```

Layer 2 is the interesting one. It's a directory with up to four optional pieces:

```
~/.config/konrad/
├── opencode.jsonc      Deep-merged with the baked default at start.
├── agents/             Your own primary agents, layered in (filenames don't conflict).
├── skills/             Your own opencode skills, layered in.
├── AGENTS.md           Personal/org model instructions, loaded on top of konrad's base.
└── fonts/              .ttf / .otf / .ttc dropped here are loaded on top of the baked palette.
```

The merge of `opencode.jsonc` is deep: **objects merge recursively, your keys win on conflict, new keys from either side come through, arrays replace.** That last one matters — see [the AGENTS.md convention](#adding-your-own-model-instructions) below.

### You declare your models

konrad pre-wires the local providers (LM Studio, Ollama, llama.cpp) at their default ports, but **the model list is yours to fill in**. Declare each model you intend to use in `~/.config/konrad/opencode.jsonc` — see the [Recipes](#recipes) below for the exact shape.

(Earlier versions shipped the [`opencode-models-discovery`](https://github.com/rivy-t/opencode-models-discovery) plugin to auto-populate the picker from each provider's `/v1/models` endpoint, but it added ~3-4 s of startup cost and tripped on LM Studio's embedding modality. An inline replacement is on the [roadmap](ROADMAP.md).)

### opencode Zen is disabled by default

opencode Zen is the upstream's paid hosted model gateway. konrad is local-first, so we disable it (`disabled_providers: ["opencode"]` in the baked default) to keep the picker focused on what you actually configured. To re-enable, override `disabled_providers` in your user config.

### Quick start: edit your override

```sh
# 1. Start your override from the baked default.
podman run --rm --entrypoint cat ghcr.io/jlbauss/konrad:latest \
  /etc/konrad/opencode-defaults.jsonc > ~/.config/konrad/opencode.jsonc

# 2. Edit it.
$EDITOR ~/.config/konrad/opencode.jsonc

# 3. Diff against the baked default to see what you changed.
diff -u <(podman run --rm --entrypoint cat ghcr.io/jlbauss/konrad:latest \
            /etc/konrad/opencode-defaults.jsonc) \
        ~/.config/konrad/opencode.jsonc
```

### Recipes

**Use Ollama instead of LM Studio.** The Ollama provider is already declared in the baked default; just register your model and switch the default:

```jsonc
// ~/.config/konrad/opencode.jsonc
{
  "provider": {
    "ollama": {
      "models": { "qwen3:30b": { "name": "Qwen 3 30B (Ollama)" } }
    }
  },
  "model": "ollama/qwen3:30b"
}
```

**Add Anthropic alongside the local providers.** Your override only adds — local engines stay available.

```jsonc
{
  "provider": {
    "anthropic": {
      "options": { "apiKey": "{env:ANTHROPIC_API_KEY}" }
    }
  },
  "model": "anthropic/claude-3-7-sonnet"
}
```

Then export `ANTHROPIC_API_KEY` on the host before running `konrad`. The CLI passes it through to the container via opencode's `{env:...}` placeholder.

**Add OpenRouter** (one key, many models):

```jsonc
{
  "provider": {
    "openrouter": {
      "npm": "@openrouter/ai-sdk-provider",
      "options": { "apiKey": "{env:OPENROUTER_API_KEY}" }
    }
  },
  "model": "openrouter/anthropic/claude-3-7-sonnet"
}
```

**Run a different model on LM Studio** (e.g. you swapped to a smaller one):

```jsonc
{
  "provider": {
    "lmstudio": {
      "models": { "your-model-id": { "name": "Friendly display name" } }
    }
  },
  "model": "lmstudio/your-model-id"
}
```

### Adding your own model instructions

konrad ships its base model instructions via the `instructions` config key. **For your own additions, use `AGENTS.md`**, which opencode discovers automatically and loads *on top of* the base:

- `~/.config/konrad/AGENTS.md` — personal or org-wide rules, loaded globally.
- `<workspace>/AGENTS.md` — per-project rules, loaded only in that workspace.

Both are additive. Don't set `instructions` in your override unless you specifically want to **replace** konrad's base — arrays don't merge.

## State and isolation

konrad splits state across three tiers, with one rule: **`.agent/` belongs to the agent.** Framework state (opencode sessions, conversation DB, logs) lives outside the workspace so the workspace stays pristine.

**Per-project, in `<workspace>/.agent/`.** The agent's working state, end-to-end. The directory is bootstrapped at every container start (so skills don't have to `mkdir -p`).

| Path | What | Lifetime |
|---|---|---|
| `.agent/task.md` | Current task's plan + outcome (planning contract) | Overwritten next task; committable. |
| `.agent/artifacts/` | Durable mid-task outputs (`manual-output.<ext>`, derived datasets, etc.) | Hands-off; committable. |
| `.agent/scratch/` | Agent-written scripts, exploration code, one-off probes | Auto-pruned >7d on every launch; gitignored. |
| `.agent/quality-assurance/<stamp>/` | Quality-assurance evidence on a failed verification (rasterized PNGs, verdict notes) | Auto-pruned >7d on every launch; gitignored. |

`konrad` auto-adds `.agent/quality-assurance/` and `.agent/scratch/` to your `.gitignore` on first run. `.agent/task.md` and `.agent/artifacts/` stay tracked because you may want to commit them.

**Centralised on the host, in `~/.local/state/konrad/log/`.** opencode's structured log files (timestamped, `+Xms` deltas per line) accumulate here across all projects, alongside a `<timestamp>-session.txt` sidecar per launch that records which host workspace was active. Standard XDG state path, easy to `tail -f`, auto-pruned >7d on every launch:

```sh
ls -t ~/.local/state/konrad/log/        # newest first
tail -f ~/.local/state/konrad/log/<file>.log
```

There's no `konrad logs` subcommand — the path is standard, and `tail`/`less`/`grep` work fine.

**Shared, in named Podman volumes.** Three things are shared across every project:

- `konrad-secrets` — `auth.json` (`/connect` credentials). You log in once, every project reuses it. Stays out of your filesystem and can't be committed by accident.
- `konrad-cache` — opencode's cache. Regeneratable; sharing means warm caches across projects.
- `konrad-state` — opencode's `~/.local/state/opencode/` directory: last-selected model, recent models per agent, other small UI-state. Shared because these preferences are about *you*, not about the project.

**Ephemeral, inside the container.** opencode's `~/.local/share/opencode/` (sessions, SQLite conversation DB) lives in the container's writable layer and dies on `--rm`. Each `konrad` run is a fresh session — durable task memory is `.agent/task.md`, not the framework's conversation DB.

The opencode binary itself is **not** in a named volume — it's installed root-owned into the image at build time, so the runtime user can't mutate it. Updates flow through `konrad --update` (or `konrad-dev --rebuild` if you're working on konrad locally).

`konrad --reset` drops the central log dir *and* all three shared volumes after a `[y/N]` prompt (next run requires a fresh `/connect`, repopulates caches, and asks you to pick a model again). For a log-only wipe, `rm -rf ~/.local/state/konrad/log/`. Workspace `.agent/` is yours — konrad never deletes it (auto-prune only touches the ephemeral subdirs).

## Pinning strategy

Every meaningful input is digest- or version-locked in [image/locks/](image/locks/). The [`.gitlab-ci.yml`](.gitlab-ci.yml) `resolve-locks` job runs on GitLab daily, re-resolves each upstream, diffs against the committed lock, and opens (auto-merges) an MR when anything moved. The merge mirrors to GitHub and triggers a real rebuild via the `image/**` path filter — so builds only fire when there is something genuinely new to build. There is no scheduled cron rebuild on GitHub.

**Locked inputs.** Each lock keys exactly one Dockerfile concern. Docker's layer cache reuses the layer when the lock is byte-identical to last time; rebuilds (and everything downstream) when it moves. Local `konrad-dev --rebuild` reads the same lock files as CI, so a developer's local build and the published image resolve to identical digests.

| Component | Lock | Source | Notes |
| --- | --- | --- | --- |
| Base image (`node:26-trixie-slim`) | `base.lock` | Docker Registry HTTP API v2 | Full ref: `name:tag@sha256:…`. Major-bump the `:tag` part by hand (e.g., `node:26 → node:27`); the bot resolves the new digest on its next run. |
| `uv` source image (`ghcr.io/astral-sh/uv:latest`) | `uv.lock` | Same | Same shape as `base.lock`. |
| Python deps (`docling-slim[standard]`, `pypdf`, `pdfplumber`, `pdf2image`, `reportlab`, `openpyxl`, `pandas`, `onnxruntime`) | `python.lock` from `python.spec` | `uv pip compile --torch-backend=cpu --python-version=3.13` | |
| `opencode-ai`, `npm` | `npm.lock` | `npm view <pkg> version` | |
| `typst` | `typst.lock` | GitHub releases API for `typst/typst` | |

The win: a typical "only opencode-ai bumped" day rebuilds only the npm layer and downstream — small user pull on the next `konrad --update`. No-op days fire no build at all — the user pull is a manifest poll only.

**Floating (one input).**

| Component | Source | Why no lock |
| --- | --- | --- |
| apt packages | Whatever Debian trixie currently ships | apt's RUN layer cache invalidates only when its parent `FROM` changes — i.e., when `base.lock` bumps. So apt naturally refreshes whenever Debian/Node ship a new base image, picking up the current package index at that point. No separate apt lock needed. |

Docling models live in their own lock (`models.lock`) — see ROADMAP for that follow-up; today they re-download whenever the Python venv layer rebuilds.

The Dockerfile [carries this list as a comment block](image/Dockerfile) at the top so the surface is visible at a glance. Keep that block and this table in sync when changing how a component is pinned.

### Tag scheme on the registry

Published at `ghcr.io/jlbauss/konrad`. CI builds run on GitHub Actions against a one-way push mirror of this repo; the primary repo stays on `gitlab.git.nrw`. See [Design decisions](#design-decisions) for why.

| Tag | Mutable? | Meaning |
| --- | --- | --- |
| `:<ver>.<date>` | immutable | e.g. `0.1.2026-05-23` — konrad codebase at that version + packages as of that day. The rollback handle. |
| `:<ver>` | rolling | Latest passing build on the current VERSION line. |
| `:latest` | rolling | Alias for the newest `<ver>` passing build. The default for `konrad --update`. |
| `:<short-sha>` | immutable | Per-commit tag, for bisecting. |

konrad's own version lives in the top-level [VERSION](VERSION) file. Bump it for any functional change to `image/`, `bin/konrad`, or baked skills/agents (date flips alone don't warrant a version bump — that's what the date tag carries). When `VERSION` bumps (e.g. `0.1 → 0.2`), the previous line stops getting new daily rebuilds; users on `:0.1` stay on their last passing build until they upgrade. Pre-1.0 simplicity; revisit at 1.0.

### Diagnosing regressions

Every published image carries `/etc/konrad/build-manifest.json` — a snapshot of dpkg / npm / pip versions plus build metadata. Dump it with `podman run --rm --entrypoint cat ghcr.io/jlbauss/konrad:latest /etc/konrad/build-manifest.json | jq .`. To diff two builds when something worked yesterday and broke today:

```sh
podman run --rm --entrypoint cat \
  ghcr.io/jlbauss/konrad:0.1.2026-05-22 \
  /etc/konrad/build-manifest.json > yesterday.json

podman run --rm --entrypoint cat \
  ghcr.io/jlbauss/konrad:0.1.2026-05-23 \
  /etc/konrad/build-manifest.json > today.json

diff <(jq -S . yesterday.json) <(jq -S . today.json)
```

The diff names every package whose version changed between the two builds, which is enough to bisect any regression to its upstream cause.

## Repo layout

```
konrad/
├── bin/konrad                       # The CLI
├── VERSION                          # konrad's current semver (drives the tag scheme)
├── .github/workflows/build-image.yml  # CI: build → smoke → publish (multi-arch: amd64 + arm64)
├── image/                           # Container build context — the canonical artifact
│   ├── Dockerfile                   # Pinning surface at the top — bump there
│   ├── entrypoint.sh                # Composes opencode.jsonc + layers user content at start
│   ├── merge-config.js              # Deep-merge for the JSONC layering
│   ├── build-manifest.sh            # Snapshot apt/npm/pip versions into /etc/konrad/build-manifest.json
│   ├── konrad-defaults/             # → /etc/konrad/ in the image (not opencode-discoverable)
│   │   └── opencode-defaults.jsonc  # Baked defaults — merged with user override at start
│   ├── opencode/                    # → ~/.config/opencode/ in the image
│   │   ├── environment.md           # Runtime environment manifest (tools, libs, layout) — loaded via instructions key
│   │   ├── agents/                  # Built-in primary agents (konrad, manual-transformer)
│   │   └── skills/                  # Bundled skills (do-it-manually, spreadsheets, pdf, quality-assurance)
│   └── fonts/konrad/                # → /usr/local/share/fonts/konrad/ (seven OFL families)
├── scripts/
│   ├── build-image.sh               # Local build — passes KONRAD_VERSION + GIT_SHA build args
│   ├── smoke-test.sh                # CI smoke gate — also runnable locally
│   ├── fetch-fonts.sh               # One-shot — pulls fonts from upstream when bumping versions
│   └── install-remote.sh            # curl|sh installer: fetches CLI standalone, bakes VERSION in
└── devcontainer/                    # Experimental: VS Code entry point as a second consumption path (see ROADMAP)
    └── devcontainer.json
```

## Design decisions

A short, opinionated record of the load-bearing choices, so future-you can tell what's a constraint and what's a preference:

- **Podman, not Docker.** Open-source, free for commercial use, ergonomic on macOS. `--userns=keep-id` lets the container's `node` user share UID with the host user, so bind-mounted files have sane ownership. Docker support is in [ROADMAP.md](ROADMAP.md).
- **The image is the canonical artifact.** `image/Dockerfile` builds `konrad:latest`. `bin/konrad` is the primary consumer; the experimental `devcontainer/devcontainer.json` is a second consumer (see [ROADMAP.md](ROADMAP.md)).
- **Layered config, not replacement.** konrad's baked `opencode.jsonc` is composed with the user's `~/.config/konrad/opencode.jsonc` at every container start via a self-contained Node deep-merger. Users add a provider without losing the defaults; konrad ships a new local engine and the user gets it automatically on next rebuild. The merge step is in `image/entrypoint.sh` and runs *before* opencode loads anything.
- **Three-tier state.** `.agent/` in the workspace belongs to the agent end-to-end (task plan, artifacts, scratch, quality-assurance evidence — see [State and isolation](#state-and-isolation)). Opencode logs land in `~/.local/state/konrad/log/` on the host (standard XDG path). Auth, cache, and small UI state live in three named Podman volumes shared across projects. Opencode sessions and the conversation DB are ephemeral (gone on container exit) — durable task memory is `.agent/task.md`, not the framework's history. See [docs/design/state-isolation.md](docs/design/state-isolation.md) for why.
- **No per-project secrets in the workspace.** Auth credentials live only in the `konrad-secrets` named volume. Users who don't read `.gitignore` carefully still can't accidentally publish their tokens.
- **`AGENTS.md` is the user's slot; `instructions` is konrad's.** opencode loads both, additively, into the system prompt. By assigning each side its own loading mechanism, we never collide.
- **Minimal hardcoded defaults.** Provider endpoints ship pre-wired but model lists ship empty — users declare whichever model they've loaded in `~/.config/konrad/opencode.jsonc`. Earlier versions auto-discovered models via the `opencode-models-discovery` plugin, but the startup cost wasn't worth it; an inline replacement is on the roadmap. **No top-level `"model"` is set in the baked default** — opencode prompts on first run, then remembers your choice in the `konrad-state` volume across subsequent runs.
- **Optimised for Qwen3.6-class local models.** The agent body in `image/opencode/agents/konrad.md` is sized and worded for a ~30B-class MoE local model — terse-but-deliberate, no Claude-style verification loops. Bigger frontier models work fine; smaller (<10B) ones may need prompt softening. The specific recommendation we test against is `qwen/qwen3.6-35b-a3b`.
- **AGPL v3.** Compatible with all bundled upstream licenses (MIT, Apache 2.0, OFL 1.1). Strong copyleft is a deliberate choice for a sandbox-style tool — if someone extends konrad or runs it as a hosted service, the improvements come back to the commons. AGPL's network-use clause closes the SaaS loophole left open by plain GPL: a fork offered as a remote agent over an API still has to publish its source.
- **Lock every input; bot maintains the locks; smoke-gate the publish.** Every meaningful input — base image, uv source image, Python deps, npm packages, Typst — is digest- or version-locked in [image/locks/](image/locks/). A GitLab bot re-resolves all of them daily; when something genuinely moved, the bot opens and auto-merges an MR, the mirror push triggers CI, and a real build runs. When nothing moved, nothing builds. The smoke test gates `:latest` so users never see a broken build. A build manifest baked into every image makes after-the-fact regression diagnosis possible — see [Pinning strategy](#pinning-strategy) for the full table and the diff recipe. Trade-off accepted: silent upstream regressions can surface as runtime breakage, but the manifest names the cause and the dated tags (`:0.1.2026-05-22`) are always rollback-eligible.
- **CI runs on a GitHub mirror; the primary repo stays on `gitlab.git.nrw`.** A one-way GitLab → GitHub push mirror replicates every commit; GitHub Actions runs the build → smoke → publish pipeline; the image lands on `ghcr.io/jlbauss/konrad`. The GitHub side is purely a CI execution surface — no issues, no MRs, no day-to-day work happens there. Why this shape: gitlab.git.nrw's shared runners don't permit the privileged-container operations Podman-in-Docker needs, and GitHub Actions gives us free hosted runners (with multi-arch coming back for free once the mirror is public). Trade-off accepted: CI status visibility lives on GitHub, not GitLab MRs, until we wire up the GitLab Commit Status API webhook.

## Troubleshooting

| Symptom                                                          | Likely cause                                | Fix                                                                                       |
| ---------------------------------------------------------------- | ------------------------------------------- | ----------------------------------------------------------------------------------------- |
| `Cannot connect to Podman` / `connection refused`                | Podman VM not running (macOS)               | `podman machine init` (once), then `podman machine start`                                 |
| `konrad: LM Studio not reachable at http://localhost:1234`       | LM Studio off or listening on a wrong port  | Open LM Studio → Developer → Start Server, port 1234. (Or you're on Ollama / llama.cpp — see [Configuration](#configuration) to set your model and ignore this warning.) |
| `EACCES: permission denied, mkdir '/home/node/.local/state'`     | Stale image (pre-permission-fix)            | `konrad --update`                                                                         |
| Agent can't find the file you mentioned                          | You ran `konrad` in the wrong directory     | The cwd is what gets mounted at `/workspace`. Always `cd` first.                          |
| `konrad: warning: LM Studio not reachable …` but you started it  | Wrong host: `host.containers.internal`      | Inside container it's `host.containers.internal`; from the host it's `localhost`. The CLI checks the host side — make sure your host `curl localhost:1234/v1/models` returns JSON. |
| `merge-config: failed to parse ~/.config/konrad/opencode.jsonc`  | Syntax error in your user override          | `cat ~/.config/konrad/opencode.jsonc` and check the JSONC syntax. Comments are fine.      |
| Want to wipe and start over                                      | —                                           | `konrad --reset` (prompts `[y/N]`), then `konrad --update`                                |

If a problem isn't listed here, run `konrad -s` to poke around inside the container with the same mounts opencode would see.

## Debugging opencode

opencode writes a fresh, timestamped log file to `~/.local/share/opencode/log/` on every launch (INFO level, `+Xms` deltas per line so a startup stall is easy to spot). konrad bind-mounts that directory to the central host path **`~/.local/state/konrad/log/`** (standard XDG state), and the container entrypoint also writes a `<timestamp>-session.txt` sidecar there recording which host workspace was active for that run.

```sh
ls -t ~/.local/state/konrad/log/                                  # newest first
tail -f ~/.local/state/konrad/log/$(ls -t ~/.local/state/konrad/log/*.log | head -1)
```

Both `*.log` and `*-session.txt` are auto-pruned >7d on every `konrad` launch, so the dir doesn't grow without bound. To wipe immediately: `rm -rf ~/.local/state/konrad/log/`.

For deeper digging, pass `-v` / `--verbose` (or export `KONRAD_DEBUG=1` for the equivalent effect). This adds per-phase timestamps to the CLI and entrypoint, and turns on Bun's `BUN_CONFIG_VERBOSE_FETCH` so every HTTP call opencode makes appears in the log. Note: `OPENCODE_LOG_LEVEL` and `DEBUG=opencode:*` don't exist in opencode's source (don't waste time setting them); the default file log is what gives you visibility.

If startup is slow, the highest-probability suspects (per opencode's own issue tracker) and the env vars that disable each:

| Knob                                     | What it disables                                              |
| ---------------------------------------- | ------------------------------------------------------------- |
| `OPENCODE_DISABLE_AUTOUPDATE=1`          | the npm registry check on every launch                        |
| `OPENCODE_DISABLE_MODELS_FETCH=1`        | the models.dev catalog fetch (we're local-first; safe to off) |
| `OPENCODE_DISABLE_LSP_DOWNLOAD=1`        | auto-install of language servers on first use                 |
| `OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1`  | scanning `.claude/skills/` (none in our container)            |
| `--pure` (CLI flag)                      | external plugins entirely — useful for bisecting plugin cost  |

Add the ones you want as env vars in `~/.config/konrad/opencode.jsonc` (via the merged config's `env` key) or pass them via `podman run -e` if iterating manually inside `konrad --shell`.

## License and attribution

konrad is released under the [GNU Affero General Public License v3.0](LICENSE). The combined work as a whole is AGPL v3; bundled third-party components retain their own (AGPL-compatible) licenses. See [NOTICE](NOTICE) for the full upstream list and copyright notices.
