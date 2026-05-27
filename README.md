<div align="center">

# Konrad

**An open-source AI coworker that runs on your machine and your models — so even your most sensitive files stay yours.**

![License: AGPL v3](https://img.shields.io/badge/license-AGPL--3.0-blue.svg)
![version](https://img.shields.io/badge/version-0.1-informational)
![status](https://img.shields.io/badge/status-alpha-orange)
![image](https://img.shields.io/badge/image-ghcr.io%2Fjlbauss%2Fkonrad-blue)

</div>

Konrad is a coworking agent that lives on your computer. Like cloud coworking agents it reads, writes, and acts on real files for you — but it runs **your** models (a trustworthy API, or fully local) against your files inside a sandboxed container, so your most private data never leaves machines you trust. That opens up work the cloud agents can't touch: filling forms with sensitive personal details, processing private notes, handling regulated data.

It's a thin, sandboxed wrapper around [opencode](https://github.com/sst/opencode): the container is the canonical artifact, the `konrad` CLI is how you run it.

## Why Konrad

- **Your data stays yours.** Run local models or a trustworthy API — handle the forms, private notes, and regulated data you'd never paste into a cloud chatbot.
- **Sandboxed by default.** The agent works inside a container that can't touch anything outside the workspace. _(Locking the network down to shrink prompt-injection blast radius is on the roadmap, not a property it has yet — see [Status](#status).)_
- **Your models, your choice.** Local engines (LM Studio / Ollama / llama.cpp) or any opencode-supported API provider — never locked to one vendor.
- **Batteries included.** One container image ships the agent's tools (ripgrep, fd, jq, pandoc, poppler, Python 3 + a system venv, Typst, LibreOffice) and a curated skill set already wired together: no venv, no pip, no host setup.
- **Fully open source.** AGPL-3.0, no telemetry, nothing proprietary.
- **Always current.** A bot tracks every upstream and CI rebuilds the image as they move; `konrad --update` keeps you fresh. See [pinning-and-build.md](docs/design/pinning-and-build.md).

What ships in the box:

- **Curated skills**, loaded via opencode's `skill` tool: `do-it-manually` (structured-but-irregular data extraction), `spreadsheets` (xlsx/csv CRUD), `pdf` (extract / edit / annotate / fill / generate), and `quality-assurance` (the cross-skill verification cycle every producer invokes before reporting). More on the way — see [ROADMAP.md](ROADMAP.md).
- **A planning contract** baked into the agent prompt: a single `.agent/task.md` per task with side effects, plus aggressive use of opencode's `todowrite` for live progress. Rationale in [task-md-and-todowrite.md](docs/design/task-md-and-todowrite.md).
- **A curated font palette** — seven SIL OFL families (Inter, Source Serif 4, Fraunces, JetBrains Mono, EB Garamond, IBM Plex Sans, Atkinson Hyperlegible) plus Debian's Noto core for broad non-Latin coverage, so generated PDFs / slides / typeset docs look intentional out of the box. Drop your own into `~/.config/konrad/fonts/` to extend.

## Status

**Alpha.** The runtime works and the build/publish pipeline is solid, but the surface area is still moving. **Don't run Konrad in production or on anything you can't afford to lose if you're not sure what you're doing.** Specifically, today:

- **No egress firewall or permission ACLs yet.** The sandbox is container + filesystem isolation only; network access is unrestricted. Narrowing it to an allow-list is the next safety milestone — see [ROADMAP.md](ROADMAP.md).
- **Podman only; Linux and macOS only.** `--userns=keep-id` is Podman-specific. Docker support is on the roadmap, untested. No Windows support — WSL is at your own discretion and untested.
- **Pre-1.0: expect churn.** Config shapes, flags, and image internals can change between versions without a migration path. No stability promise until 1.0.
- **No automated test suite.** Validation is manual (shellcheck + a smoke build). Regressions can slip through; the baked build manifest is the safety net, not a test suite.
- **Local-model UX is still rough.** Tool-call parsing, context overflow, and model switching have known edges — the "works flawlessly on local models" shakedown is still a roadmap item. You must also hand-declare each loaded model (no auto-discovery yet).

## Who it's for

Konrad is for someone who wants an AI agent to work on **their own files, on their own machine, with their own models** — especially when the data is too sensitive to send to a hosted service.

**It's probably not for you if you want:**

- **Coding / software development** — use Claude Code, Cursor, and the like; Konrad isn't tuned as a coding agent.
- **Research or web-heavy work** — deep-research and browsing agents do this better. Konrad has no browsing stack, and is moving *toward* tighter network isolation, not away from it.
- **Production, hosted, or multi-user deployment** — it's a single-user local sandbox, not a deployable service.
- **A zero-config cloud agent** — if you just want a hosted frontier model with no setup, a first-party app is less friction. Konrad's payoff is local + your-files + sandbox.

## Install

One-liner, no clone needed:

```sh
curl -fsSL https://gitlab.git.nrw/jbauss2/konrad/-/raw/main/scripts/install-remote.sh | sh
```

This drops `konrad` into `~/.local/bin/` (override with `KONRAD_INSTALL_DIR=…`), pre-pulls the container image (skippable with `KONRAD_NO_PULL=1`), and warns if you need to install Podman or fix your `PATH`. Re-run any time to upgrade in place. The first `konrad` run also auto-pulls if the image isn't present, so the explicit pre-pull is optional; if the registry is unreachable, Konrad falls back to a (much slower) local build.

### Requirements

- **[Podman](https://podman.io/).** On macOS: `podman machine init` once, then `podman machine start`.
- **A model provider.** Konrad pre-wires three local engines at their default ports — [LM Studio](https://lmstudio.ai/) (`:1234`), [Ollama](https://ollama.com/) (`:11434`), [llama.cpp](https://github.com/ggerganov/llama.cpp) (`:8080`) — and any opencode-supported API provider (Anthropic, OpenAI, OpenRouter, Gemini, …) works via a small config override. **No models ship declared** — you list the ones you've loaded yourself (see [Configuration](#configuration)).
- **Recommended model class.** Konrad's skills and prompts are tuned for a **30B-class open-weight model with strong agentic ability** — we test against [`qwen/qwen3.6-27b`](https://lmstudio.ai/models/qwen/qwen3.6-27b). Models should have **native vision**, a context window **≥ 256k**, and agentic strength at least on par with Qwen3.6 27B ([Artificial Analysis Agentic Index](https://artificialanalysis.ai/models/capabilities/agentic)). Stronger models only help. As of 2026-05-20, qualifying picks include Qwen3.6 27B and Kimi K2.6 (open weights); Claude Sonnet/Opus ≥ 4.6, GPT ≥ 5.4, and Gemini 3.5 Flash (proprietary).

Working on Konrad itself? See [CONTRIBUTING.md](CONTRIBUTING.md) for the parallel `konrad-dev` CLI that tracks your checkout.

## Use

```sh
cd ~/wherever-you-keep-the-files-the-agent-will-touch
konrad
```

That's the whole UX: the current directory is mounted at `/workspace` inside the container, opencode starts pointing at your configured provider, and you go.

### Flags

| Flag                     | What it does                                                            |
| ------------------------ | ----------------------------------------------------------------------- |
| _(none)_                 | Default. Runs opencode against the current directory.                   |
| `-s`, `--shell`          | Open a bash shell in the container instead of opencode.                 |
| `-v`, `--verbose`        | Per-phase timestamps + verbose opencode logs. Useful for chasing slow startup. |
| `--version`              | Print CLI version + image tag/digest/revision.                          |
| `--update`               | Pull the latest image from `ghcr.io/jlbauss/konrad:latest` and refresh the CLI script itself. |
| `--reset`                | Wipe shared volumes + log dir. Prompts `[y/N]`; affects all workspaces. |
| `--uninstall`            | Remove the CLI binary + the image. Prompts `[y/N]`. Leaves user config, shared volumes, and log dir alone. |
| `-h`, `--help`           | Show usage.                                                             |

Short flags bundle (`konrad -sv` is `konrad -s -v`). `konrad-dev` is the contributor binary — same flags, except `--rebuild` replaces `--update`. See [CONTRIBUTING.md](CONTRIBUTING.md).

### Occasional maintenance (one-liners)

| Goal                                 | Command                                                                                       |
| ------------------------------------ | --------------------------------------------------------------------------------------------- |
| Edit your user override              | `$EDITOR ~/.config/konrad/opencode.jsonc`                                                     |
| Start from the baked default         | `podman run --rm --entrypoint cat ghcr.io/jlbauss/konrad:latest /etc/konrad/opencode-defaults.jsonc > ~/.config/konrad/opencode.jsonc` |
| Diff your override vs. baked default | `diff -u <(podman run --rm --entrypoint cat ghcr.io/jlbauss/konrad:latest /etc/konrad/opencode-defaults.jsonc) ~/.config/konrad/opencode.jsonc` |
| Clear just the log dir               | `rm -rf ~/.local/state/konrad/log/`                                                           |
| Nuclear reset                        | `konrad --reset` (wipes log dir + all shared volumes; prompts `[y/N]`)                        |

## Configuration

Konrad composes opencode's runtime config from up to three layers at container start. **You only override what you want to change**; everything else stays inherited.

```
Layer 1 — Baked defaults     /etc/konrad/opencode-defaults.jsonc   (in the image)
Layer 2 — Your overrides     ~/.config/konrad/                     (on the host)
Layer 3 — Per-project        <workspace>/.opencode/opencode.json   (opencode-native)
```

Layer 2 is the interesting one — a directory with up to four optional pieces:

```
~/.config/konrad/
├── opencode.jsonc      Deep-merged with the baked default at start.
├── agents/             Your own primary agents, layered in.
├── skills/             Your own opencode skills, layered in.
├── AGENTS.md           Personal/org model instructions, loaded on top of Konrad's base.
└── fonts/              .ttf / .otf / .ttc dropped here load on top of the baked palette.
```

The merge of `opencode.jsonc` is deep: **objects merge recursively, your keys win on conflict, new keys from either side come through, arrays replace.** That last one matters — see [the AGENTS.md convention](#adding-your-own-model-instructions).

### You declare your models

Konrad pre-wires the local providers at their default ports, but **the model list is yours to fill in**. Declare each model you intend to use in `~/.config/konrad/opencode.jsonc` — see the [Recipes](#recipes) below. (Auto-discovery used to live here via the [`opencode-models-discovery`](https://github.com/rivy-t/opencode-models-discovery) plugin, but it added ~3-4 s of startup and tripped on LM Studio's embedding modality; an inline replacement is on the [roadmap](ROADMAP.md).)

opencode Zen — the upstream's paid hosted gateway — is **disabled by default** (`disabled_providers: ["opencode"]`), since Konrad is local-first. Override `disabled_providers` to re-enable.

### Quick start: edit your override

```sh
# 1. Start from the baked default.
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

**Use Ollama instead of LM Studio** (the provider is already declared; register your model and switch the default):

```jsonc
// ~/.config/konrad/opencode.jsonc
{
  "provider": { "ollama": { "models": { "qwen3:30b": { "name": "Qwen 3 30B (Ollama)" } } } },
  "model": "ollama/qwen3:30b"
}
```

**Add Anthropic alongside the local providers** (your override only adds — local engines stay available):

```jsonc
{
  "provider": { "anthropic": { "options": { "apiKey": "{env:ANTHROPIC_API_KEY}" } } },
  "model": "anthropic/claude-sonnet-4-6"
}
```

Then export `ANTHROPIC_API_KEY` on the host before running `konrad`; the CLI passes it through via opencode's `{env:...}` placeholder.

**Add OpenRouter** (one key, many models):

```jsonc
{
  "provider": {
    "openrouter": {
      "npm": "@openrouter/ai-sdk-provider",
      "options": { "apiKey": "{env:OPENROUTER_API_KEY}" }
    }
  },
  "model": "openrouter/anthropic/claude-sonnet-4-6"
}
```

**Run a different model on LM Studio:**

```jsonc
{
  "provider": { "lmstudio": { "models": { "your-model-id": { "name": "Friendly display name" } } } },
  "model": "lmstudio/your-model-id"
}
```

### Adding your own model instructions

Konrad ships its base instructions via the `instructions` config key. **For your own additions, use `AGENTS.md`**, which opencode discovers automatically and loads *on top of* the base:

- `~/.config/konrad/AGENTS.md` — personal or org-wide rules, loaded globally.
- `<workspace>/AGENTS.md` — per-project rules, loaded only in that workspace.

Both are additive. Don't set `instructions` in your override unless you specifically want to **replace** Konrad's base — arrays don't merge.

## State

One rule: **`.agent/` belongs to the agent.** Framework state (opencode sessions, conversation DB, logs) lives outside the workspace so your project stays pristine.

| Where | What | Lifetime |
|---|---|---|
| `<workspace>/.agent/task.md` | Current task's plan + outcome | Overwritten next task; committable. |
| `<workspace>/.agent/artifacts/` | Durable mid-task outputs | Hands-off; committable. |
| `<workspace>/.agent/scratch/`, `.agent/quality-assurance/` | Agent scripts; verification evidence | Auto-pruned >7d; gitignored (added on first run). |
| `~/.local/state/konrad/log/` | opencode logs + per-launch session sidecar | Auto-pruned >7d; `ls -t` / `tail -f`. |
| Named volumes `konrad-secrets` / `-cache` / `-state` | Auth, cache, last-model + UI state | Shared across projects; wiped by `konrad --reset`. |

opencode's sessions and conversation DB are **ephemeral** — gone on container exit. Durable task memory is `.agent/task.md`, not the framework's history. Full rationale and the exact mount topology in [state-isolation.md](docs/design/state-isolation.md).

## Troubleshooting

| Symptom                                                          | Likely cause                                | Fix                                                                                       |
| ---------------------------------------------------------------- | ------------------------------------------- | ----------------------------------------------------------------------------------------- |
| `Cannot connect to Podman` / `connection refused`                | Podman VM not running (macOS)               | `podman machine init` (once), then `podman machine start`                                 |
| `LM Studio not reachable at http://localhost:1234`               | LM Studio off or on a wrong port            | LM Studio → Developer → Start Server, port 1234. (Or you're on Ollama / llama.cpp — set your model in [Configuration](#configuration) and ignore the warning.) |
| `EACCES: permission denied, mkdir '/home/node/.local/state'`     | Stale image (pre-permission-fix)            | `konrad --update`                                                                         |
| Agent can't find the file you mentioned                          | You ran `konrad` in the wrong directory     | The cwd is what gets mounted at `/workspace`. Always `cd` first.                          |
| `merge-config: failed to parse ~/.config/konrad/opencode.jsonc`  | Syntax error in your user override          | `cat` it and check the JSONC syntax. Comments are fine.                                   |
| Want to wipe and start over                                      | —                                           | `konrad --reset` (prompts `[y/N]`), then `konrad --update`                                |

If a problem isn't listed here, run `konrad -s` to poke around inside the container with the same mounts opencode would see.

### Debugging opencode

opencode writes a fresh, timestamped log on every launch; Konrad bind-mounts it to **`~/.local/state/konrad/log/`** (standard XDG state) and writes a `<timestamp>-session.txt` sidecar recording which host workspace was active.

```sh
ls -t ~/.local/state/konrad/log/                                  # newest first
tail -f ~/.local/state/konrad/log/$(ls -t ~/.local/state/konrad/log/*.log | head -1)
```

For deeper digging, pass `-v` / `--verbose` (or export `KONRAD_DEBUG=1`): per-phase timestamps plus Bun's `BUN_CONFIG_VERBOSE_FETCH` so every HTTP call appears in the log. If startup is slow, the usual suspects and the env vars that disable each (set them via the merged config's `env` key):

| Knob                                     | What it disables                                              |
| ---------------------------------------- | ------------------------------------------------------------- |
| `OPENCODE_DISABLE_AUTOUPDATE=1`          | the npm registry check on every launch                        |
| `OPENCODE_DISABLE_MODELS_FETCH=1`        | the models.dev catalog fetch (we're local-first; safe to off) |
| `OPENCODE_DISABLE_LSP_DOWNLOAD=1`        | auto-install of language servers on first use                 |
| `OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1`  | scanning `.claude/skills/` (none in our container)            |
| `--pure` (CLI flag)                      | external plugins entirely — useful for bisecting plugin cost  |

## Internals

How Konrad is built and why — for the curious and for contributors:

- **Pinning & build cache** → [docs/design/pinning-and-build.md](docs/design/pinning-and-build.md)
- **Versioning & release tags** → [docs/design/versioning-and-releases.md](docs/design/versioning-and-releases.md)
- **State & isolation** → [docs/design/state-isolation.md](docs/design/state-isolation.md)
- **Planning contract (`task.md` + `todowrite`)** → [docs/design/task-md-and-todowrite.md](docs/design/task-md-and-todowrite.md)
- **Design decisions** → [docs/design/design-decisions.md](docs/design/design-decisions.md)
- **Repo layout, dev loop, contributing** → [CONTRIBUTING.md](CONTRIBUTING.md)

## License and attribution

Konrad is released under the [GNU Affero General Public License v3.0](LICENSE). The combined work as a whole is AGPL v3; bundled third-party components retain their own (AGPL-compatible) licenses. See [NOTICE](NOTICE) for the full upstream list and copyright notices.

---

<sub>The project is **Konrad** (it's a name); the command, image, and paths are `konrad`, lowercase — that's code.</sub>
