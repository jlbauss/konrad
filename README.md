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

```sh
git clone <this-repo> ~/src/konrad
cd ~/src/konrad
./scripts/install.sh        # symlinks bin/konrad into ~/.local/bin
./scripts/build-image.sh    # builds the konrad:latest image (one-time, ~5 min)
```

Make sure `~/.local/bin` is on your `PATH`. The installer warns if it isn't.

## Use

```sh
cd ~/wherever-you-keep-the-files-the-agent-will-touch
konrad
```

That's the whole UX: the current directory is mounted at `/workspace` inside the container, opencode starts pointing at LM Studio (or whatever you've configured), and you go.

### Subcommands

| Command                | What it does                                                          |
| ---------------------- | --------------------------------------------------------------------- |
| `konrad`               | Default. Runs opencode against the current directory.                 |
| `konrad shell`         | Opens a bash shell in the container — same mounts, no agent.          |
| `konrad rebuild`       | Rebuilds the `konrad:latest` image from this repo's `image/`.         |
| `konrad clean`         | Removes the central log dir at `~/.local/state/konrad/log/`.          |
| `konrad clean --all`   | Also drops the shared volumes (auth, cache, opencode state). Forces fresh login. |
| `konrad config init`   | Copies the baked default `opencode.jsonc` to your user override.      |
| `konrad config path`   | Prints the path of your user override.                                |
| `konrad config show`   | Diffs your user override against the baked default.                   |
| `konrad version`       | Prints CLI version and image info.                                    |
| `konrad help`          | Show usage.                                                           |

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
konrad config init          # copies the baked default to ~/.config/konrad/opencode.jsonc
$EDITOR "$(konrad config path)"
konrad config show          # diff against the baked default to see what you changed
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

The opencode binary itself is **not** in a named volume — it's installed root-owned into the image at build time, so the runtime user can't mutate it. Updates flow through `konrad rebuild`.

`konrad clean` wipes the central log dir (`~/.local/state/konrad/log/`). `konrad clean --all` *also* drops all three shared volumes (next run requires a fresh `/connect`, repopulates caches, and asks you to pick a model again). Workspace `.agent/` is yours — konrad never deletes it (auto-prune only touches the ephemeral subdirs).

## Repo layout

```
konrad/
├── bin/konrad                       # The CLI
├── image/                           # Container build context — the canonical artifact
│   ├── Dockerfile
│   ├── entrypoint.sh                # Composes opencode.jsonc + layers user content at start
│   ├── merge-config.js              # Deep-merge for the JSONC layering
│   ├── konrad-defaults/             # → /etc/konrad/ in the image (not opencode-discoverable)
│   │   ├── opencode-defaults.jsonc  # Baked defaults — merged with user override at start
│   │   └── instructions.md          # konrad's base instructions, loaded via instructions key
│   ├── opencode/                    # → ~/.config/opencode/ in the image
│   │   ├── agents/                  # Built-in primary agents (konrad, manual-transformer)
│   │   └── skills/                  # Bundled skills (do-it-manually, spreadsheets, pdf, quality-assurance)
│   └── fonts/konrad/                # → /usr/local/share/fonts/konrad/ (seven OFL families)
├── scripts/
│   ├── build-image.sh               # `podman build -t konrad:latest image/`
│   ├── fetch-fonts.sh               # One-shot — pulls fonts from upstream when bumping versions
│   └── install.sh                   # Symlinks bin/konrad into ~/.local/bin
└── devcontainer/                    # Experimental: VS Code entry point as a second consumption path (see ROADMAP)
    └── devcontainer.json
```

## Two ways to work with konrad

**Using konrad as a user.** Install once with the steps above. From then on, `cd` to whatever folder you want the agent to operate on and run `konrad`. The konrad repo only matters for getting the image and CLI installed; you don't open it day-to-day.

**Hacking on konrad itself.** Clone the repo and edit. Changes to `bin/konrad` take effect immediately; changes anywhere under `image/` need a rebuild (`konrad rebuild` or `./scripts/build-image.sh`) to land in `konrad:latest`. See [CONTRIBUTING.md](CONTRIBUTING.md) for the development loop. (The `devcontainer/` folder is an experimental second consumption path — not the recommended dev environment yet; see [ROADMAP.md](ROADMAP.md).)

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

## Troubleshooting

| Symptom                                                          | Likely cause                                | Fix                                                                                       |
| ---------------------------------------------------------------- | ------------------------------------------- | ----------------------------------------------------------------------------------------- |
| `Cannot connect to Podman` / `connection refused`                | Podman VM not running (macOS)               | `podman machine init` (once), then `podman machine start`                                 |
| `konrad: LM Studio not reachable at http://localhost:1234`       | LM Studio off or listening on a wrong port  | Open LM Studio → Developer → Start Server, port 1234. (Or you're on Ollama / llama.cpp — see [Configuration](#configuration) to set your model and ignore this warning.) |
| `EACCES: permission denied, mkdir '/home/node/.local/state'`     | Stale image (pre-permission-fix)            | `konrad rebuild`                                                                          |
| Agent can't find the file you mentioned                          | You ran `konrad` in the wrong directory     | The cwd is what gets mounted at `/workspace`. Always `cd` first.                          |
| `konrad: warning: LM Studio not reachable …` but you started it  | Wrong host: `host.containers.internal`      | Inside container it's `host.containers.internal`; from the host it's `localhost`. The CLI checks the host side — make sure your host `curl localhost:1234/v1/models` returns JSON. |
| `merge-config: failed to parse ~/.config/konrad/opencode.jsonc`  | Syntax error in your user override          | `konrad config show` to see the file; check the JSONC syntax. Comments are fine.          |
| Want to wipe and start over                                      | —                                           | `konrad clean --all`, then `konrad rebuild`                                               |

If a problem isn't listed here, run `konrad shell` to poke around inside the container with the same mounts opencode would see.

## Debugging opencode

opencode writes a fresh, timestamped log file to `~/.local/share/opencode/log/` on every launch (INFO level, `+Xms` deltas per line so a startup stall is easy to spot). konrad bind-mounts that directory to the central host path **`~/.local/state/konrad/log/`** (standard XDG state), and the container entrypoint also writes a `<timestamp>-session.txt` sidecar there recording which host workspace was active for that run.

```sh
ls -t ~/.local/state/konrad/log/                                  # newest first
tail -f ~/.local/state/konrad/log/$(ls -t ~/.local/state/konrad/log/*.log | head -1)
```

Both `*.log` and `*-session.txt` are auto-pruned >7d on every `konrad` launch, so the dir doesn't grow without bound. To wipe immediately: `konrad clean`.

For deeper digging, set `KONRAD_DEBUG=1` before invoking konrad. This adds per-phase timestamps to the CLI and entrypoint, and turns on Bun's `BUN_CONFIG_VERBOSE_FETCH` so every HTTP call opencode makes appears in the log. Note: `OPENCODE_LOG_LEVEL` and `DEBUG=opencode:*` don't exist in opencode's source (don't waste time setting them); the default file log is what gives you visibility.

If startup is slow, the highest-probability suspects (per opencode's own issue tracker) and the env vars that disable each:

| Knob                                     | What it disables                                              |
| ---------------------------------------- | ------------------------------------------------------------- |
| `OPENCODE_DISABLE_AUTOUPDATE=1`          | the npm registry check on every launch                        |
| `OPENCODE_DISABLE_MODELS_FETCH=1`        | the models.dev catalog fetch (we're local-first; safe to off) |
| `OPENCODE_DISABLE_LSP_DOWNLOAD=1`        | auto-install of language servers on first use                 |
| `OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1`  | scanning `.claude/skills/` (none in our container)            |
| `--pure` (CLI flag)                      | external plugins entirely — useful for bisecting plugin cost  |

Add the ones you want as env vars in `~/.config/konrad/opencode.jsonc` (via the merged config's `env` key) or pass them via `podman run -e` if iterating manually inside `konrad shell`.

## License and attribution

konrad is released under the [GNU Affero General Public License v3.0](LICENSE). The combined work as a whole is AGPL v3; bundled third-party components retain their own (AGPL-compatible) licenses. See [NOTICE](NOTICE) for the full upstream list and copyright notices.
