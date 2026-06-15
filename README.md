<div align="center">

# Konrad

**An open-source AI coworker that runs on your machine and your models — so even your most sensitive files stay yours.**

[![License: AGPL v3](https://img.shields.io/badge/license-AGPL--3.0-blue.svg)](LICENSE)
[![version](https://img.shields.io/badge/dynamic/yaml?url=https://gitlab.git.nrw/jbauss2/konrad/-/raw/main/VERSION&query=$&label=version&color=informational)](CHANGELOG.md)
[![status](https://img.shields.io/badge/status-alpha-orange)](#status)
[![image](https://img.shields.io/badge/image-ghcr.io%2Fjlbauss%2Fkonrad-blue)](https://github.com/users/jlbauss/packages/container/package/konrad)

</div>

Konrad is a coworking agent that lives on your computer. Like cloud coworking agents it reads, writes, and acts on real files for you — but it runs **your** models (a trustworthy API, or fully local) against your files inside a sandboxed container, so your most private data never leaves machines you trust. That opens up work the cloud agents can't touch: filling forms with sensitive personal details, processing private notes, handling regulated data.

It's a thin, sandboxed wrapper around [opencode](https://github.com/sst/opencode): the container is the canonical artifact, the `konrad` CLI is how you run it.

## Why Konrad

- **Your data stays yours.** Run local models or a trustworthy API — handle the forms, private notes, and regulated data you'd never paste into a cloud chatbot.
- **Sandboxed by default.** The agent works inside a container that can't touch anything outside the workspace, and an egress firewall (on by default) restricts its network to an allow-list — your model providers plus a small trusted set — so a prompt-injected agent can't quietly ship your data off the box.
- **Your models, your choice.** Local engines (LM Studio / Ollama / llama.cpp) or any opencode-supported API provider — never locked to one vendor.
- **Batteries included.** One container image ships the agent's tools (ripgrep, fd, jq, pandoc, poppler, Python 3 + a system venv, Typst, LibreOffice) and a curated skill set already wired together: no venv, no pip, no host setup.
- **Fully open source.** AGPL-3.0, no telemetry, nothing proprietary.
- **Always current.** A bot tracks every upstream and CI rebuilds the image as they move; `konrad --update` keeps you fresh. See [build & reproducibility](ARCHITECTURE.md#build--reproducibility).

What ships in the box:

- **Curated skills**, loaded via opencode's `skill` tool: `do-it-manually` (structured-but-irregular data extraction), `spreadsheets` (xlsx/csv CRUD), `pdf` (extract / edit / annotate / fill / generate), and `quality-assurance` (the cross-skill verification cycle every producer invokes before reporting). More on the way — see [ROADMAP.md](ROADMAP.md).
- **A planning contract** baked into the agent prompt: a single `.agent/task.md` per task with side effects, plus aggressive use of opencode's `todowrite` for live progress. Rationale in [the planning contract](ARCHITECTURE.md#the-planning-contract).
- **A curated font palette** — seven SIL OFL families (Inter, Source Serif 4, Fraunces, JetBrains Mono, EB Garamond, IBM Plex Sans, Atkinson Hyperlegible) plus Debian's Noto core for broad non-Latin coverage, so generated PDFs / slides / typeset docs look intentional out of the box. Drop your own into `~/.config/konrad/user/fonts/` to extend.

## Status

**Alpha.** The runtime works and the build/publish pipeline is solid, but the surface area is still moving. **Don't run Konrad in production or on anything you can't afford to lose if you're not sure what you're doing.** Specifically, today:

- **Egress firewall on by default; no permission ACLs yet.** Network egress is restricted to an allow-list (your providers + a small trusted set) by a sidecar filtering proxy — `--no-firewall` opts out, `--allow-host` widens it. Per-tool permission ACLs and read-only-workspace mode are still on the roadmap — see [ROADMAP.md](ROADMAP.md).
- **Podman only; Linux and macOS only.** `--userns=keep-id` is Podman-specific. Docker support is on the roadmap, untested. No Windows support — WSL is at your own discretion and untested.
- **Pre-1.0: expect churn, but versioned.** Konrad uses [semantic versioning](CONTRIBUTING.md#versioning) — pre-1.0 that's `0.X.Y` (`X`/minor = new functionality or any user-visible change, `Y`/patch = fixes). The leading `0.` means config shapes, flags, and image internals can still change without a migration path; no stability promise until 1.0.
- **No automated test suite.** Validation is manual (shellcheck + a smoke build). Regressions can slip through; the baked build manifest is the safety net, not a test suite.
- **Local-model UX is still rough.** Tool-call parsing, context overflow, and model switching have known edges — the "works flawlessly on local models" shakedown is still a roadmap item. You must also hand-declare each loaded model (no auto-discovery yet).

## Who it's for

Konrad is for someone who wants an AI agent to work on **their own files, on their own machine, with their own models** — especially when the data is too sensitive to send to a hosted service.

**It's probably not for you if you want:**

- **Coding / software development** — use Claude Code, Cursor, and the like; Konrad isn't tuned as a coding agent.
- **Research or web-heavy work** — deep-research and browsing agents do this better. Konrad has no browsing stack, and its default-on egress firewall deliberately narrows network access — it's built to stay on a leash, not to roam.
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
- **A model provider.** Any opencode-supported API provider (OpenRouter, Anthropic, OpenAI, Gemini, …) works out of the box — `/connect` it in the TUI, no config. Local engines ([LM Studio](https://lmstudio.ai/) `:1234`, [Ollama](https://ollama.com/) `:11434`, [llama.cpp](https://github.com/ggerganov/llama.cpp) `:8080`) are pre-wired too; for those you declare the model you've loaded (no auto-discovery yet). See [Configuration](#configuration).
- **Recommended model class.** Konrad's skills and prompts are tuned for a **30B-class open-weight model with strong agentic ability** — we test against [`qwen/qwen3.6-27b`](https://huggingface.co/Qwen). Models should have **native vision**, a context window **≥ 256k**, and agentic strength at least on par with Qwen3.6 27B ([Artificial Analysis Agentic Index](https://artificialanalysis.ai/models/capabilities/agentic)). Stronger models only help. As of 2026-05-20, qualifying picks include Qwen3.6 27B and Kimi K2.6 (open weights); Claude Sonnet/Opus ≥ 4.6, GPT ≥ 5.4, and Gemini 3.5 Flash (proprietary).

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
| `--no-firewall`          | Disable the egress firewall for this run (default ON). Restores unrestricted network access. |
| `--allow-host <host>`    | Add a host to the egress allow-list for this run (repeatable). Permanent entries go in `~/.config/konrad/user/allowed_hosts`. |
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
| Edit your user override              | `$EDITOR ~/.config/konrad/user/opencode.jsonc`                                                     |
| Start from the baked default         | `podman run --rm --entrypoint cat ghcr.io/jlbauss/konrad:latest /etc/konrad/opencode-defaults.jsonc > ~/.config/konrad/user/opencode.jsonc` |
| Diff your override vs. baked default | `diff -u <(podman run --rm --entrypoint cat ghcr.io/jlbauss/konrad:latest /etc/konrad/opencode-defaults.jsonc) ~/.config/konrad/user/opencode.jsonc` |
| Clear just the log dir               | `rm -rf ~/.local/state/konrad/log/`                                                           |
| Nuclear reset                        | `konrad --reset` (wipes log dir + all shared volumes; prompts `[y/N]`)                        |

## Configuration

Konrad composes opencode's runtime config from up to four layers at container start. **You only override what you want to change**; everything else stays inherited.

```
Layer 1 — Baked defaults     /etc/konrad/opencode-defaults.jsonc   (in the image)
Layer 2 — Org defaults       ~/.config/konrad/org/                 (on the host, optional)
Layer 3 — Your overrides     ~/.config/konrad/user/                (on the host)
Layer 4 — Per-project        <workspace>/.opencode/opencode.json   (opencode-native)
```

Layers 2 and 3 are symmetric — each is a directory with up to five optional pieces:

```
~/.config/konrad/
├── org/                Optional. Shipped by your organization (see "For organizations").
│   └── …same five pieces as user/…
└── user/               Your personal layer.
    ├── opencode.jsonc  Deep-merged with the baked default (and any org layer) at start.
    ├── agents/         Your own primary agents, layered in.
    ├── skills/         Your own opencode skills, layered in.
    ├── AGENTS.md       Personal model instructions, loaded on top of Konrad's base.
    ├── fonts/          .ttf / .otf / .ttc dropped here load on top of the baked palette.
    └── allowed_hosts   Extra egress-firewall hosts, one per line (see Egress firewall).
```

(The first five are opencode config, deep-merged at start. `allowed_hosts` is the one Konrad-specific extra — it feeds the egress firewall, not opencode.)

The merge of `opencode.jsonc` is deep and ordered **baked < org < user** (last writer wins): **objects merge recursively, the later layer's keys win on conflict, new keys from any layer come through, arrays replace.** That last one matters — see [the AGENTS.md convention](#adding-your-own-model-instructions).

> **Upgrading from a pre-0.4 install?** Konrad used to keep your config flat at `~/.config/konrad/{opencode.jsonc,agents,…}`. The first run of 0.4+ moves those into `~/.config/konrad/user/` automatically and prints a one-line notice — nothing for you to do.

### Set up a model provider

**The standard way is `/connect`.** Launch `konrad`, run `/connect` in the TUI, pick your provider (OpenRouter, Anthropic, OpenAI, Gemini, …) and paste a key — or do the browser login. opencode stores the credential in the `konrad-secrets` volume (`auth.json`), never in your config or host environment; it lists that provider's models in the picker (from the bundled [models.dev](https://models.dev) catalog — nothing to declare); and the egress firewall allows the provider automatically, live-reloading mid-session. No file editing.

Prefer to authenticate without launching the TUI — or doing an **OAuth** login (Claude Pro/Max, Copilot)? Run **`konrad connect`** (`konrad connect -p <provider>` to skip the picker). It runs `opencode auth login` with no agent in the loop and the firewall off, so even an OAuth first-connect needs no `--allow-host` (see [Egress firewall](#egress-firewall)).

Editing `opencode.jsonc` is only needed to:

- **declare a local model** — the local engines (LM Studio / Ollama / llama.cpp) are pre-wired at their default ports, but there's no model auto-discovery yet, so you list what you've loaded (recipe below). *(The [`opencode-models-discovery`](https://github.com/rivy-t/opencode-models-discovery) plugin used to do this but cost ~3-4 s of startup; an inline replacement is on the [roadmap](ROADMAP.md).)*
- **add a custom / self-hosted endpoint** — anything not in the models.dev catalog needs an explicit `baseURL` (recipe below).

opencode Zen — the upstream's paid hosted gateway — is **disabled by default** (`disabled_providers: ["opencode"]`). Override `disabled_providers` to re-enable.

### Egress firewall

The agent runs on an isolated container network with **no direct route to the internet**. A sidecar — the same Konrad image launched as a filtering proxy — is the only thing with egress, and it forwards traffic only to an allow-list, refusing everything else (default-deny). This shrinks the blast radius if the agent is prompt-injected: it can't quietly POST your workspace or credentials to an arbitrary host.

The allow-list is assembled at launch from:

- **your model providers**, derived automatically — both the ones you **declare** in `opencode.jsonc` (local `host.containers.internal` and any remote API host alike) and the built-in ones you **connect** with `/connect` (OpenRouter, Anthropic, OpenAI, …). Built-in providers carry no URL in your config, so Konrad resolves them to a host via a baked map generated from [models.dev](https://models.dev). Connecting a provider mid-session just works — the firewall live-reloads within a couple of seconds, no restart needed;
- **`registry.npmjs.org`**, where opencode fetches a provider's SDK adapter on demand (the OpenAI-compatible adapter that backs the local engines is already bundled; Anthropic/Google-style SDKs are pulled on first use);
- **your own additions** — list hosts (one per line, `#` comments) in `~/.config/konrad/user/allowed_hosts` (or the org layer's), or pass `--allow-host <host>` for a single run.

> One edge: an **OAuth** login (e.g. Claude Pro/Max) does its handshake *before* the credential is saved, so that first connect can't be auto-allowed mid-session. The clean path is **`konrad connect`** — it authenticates with the firewall off (safe: no agent is running), so no `--allow-host` is needed. (Doing it inside a normal session instead? Pass `--allow-host <provider-host>` once, or `--no-firewall`.) API-key providers have no such step.

Deliberately **not** in the default set: `models.dev` (the external model catalog — opencode bundles a snapshot and Konrad bakes the provider-host map from it, so the live site isn't needed at runtime), PyPI (`pip install` — the image already ships a full venv; `--allow-host pypi.org files.pythonhosted.org` when you genuinely need to extend it), and the open web. Add what your task needs.

It's **on by default**. Turn it off for a run with `konrad --no-firewall`. When the agent reports a host is blocked, that's the firewall doing its job — add the host if you trust it. (Why a proxy and not a raw IP block: remote providers sit behind rotating cloud IPs, so the allow-list is by *hostname*. Full design in [ARCHITECTURE.md](ARCHITECTURE.md#state-secrets--isolation).)

### Quick start: edit your override

```sh
# 1. Start from the baked default.
podman run --rm --entrypoint cat ghcr.io/jlbauss/konrad:latest \
  /etc/konrad/opencode-defaults.jsonc > ~/.config/konrad/user/opencode.jsonc

# 2. Edit it.
$EDITOR ~/.config/konrad/user/opencode.jsonc

# 3. Diff against the baked default to see what you changed.
diff -u <(podman run --rm --entrypoint cat ghcr.io/jlbauss/konrad:latest \
            /etc/konrad/opencode-defaults.jsonc) \
        ~/.config/konrad/user/opencode.jsonc
```

### Recipes

For a **catalog provider** (OpenRouter, Anthropic, OpenAI, …) you don't need a recipe — just `/connect` (above). These two cases are the reason to edit `opencode.jsonc`:

**Declare a local model** (the engine is pre-wired — register the model you've loaded and make it the default):

```jsonc
// ~/.config/konrad/user/opencode.jsonc — Ollama shown; swap in lmstudio or llamacpp
{
  "provider": { "ollama": { "models": { "qwen3:30b": { "name": "Qwen 3 30B" } } } },
  "model": "ollama/qwen3:30b"
}
```

All three local engines are pre-wired at their default ports (LM Studio `:1234`, Ollama `:11434`, llama.cpp `:8080`); you only declare the model.

**Add a custom / self-hosted endpoint** (any OpenAI-compatible URL not in the models.dev catalog). The first-class way is **`konrad connect --custom`** — it prompts for the id, base URL, and a model, writes the declaration into your user layer for you, then walks you through the key step (no `--allow-host`, the firewall is off for auth). If your org layer already declares the provider, run the same command and it skips straight to the key.

To do it by hand instead, the declaration is just:

```jsonc
{
  "provider": {
    "my-endpoint": {
      "npm": "@ai-sdk/openai-compatible",
      "options": { "baseURL": "https://llm.internal.example/v1", "apiKey": "{env:MY_KEY}" },
      "models": { "my-model": { "name": "My Model" } }
    }
  },
  "model": "my-endpoint/my-model"
}
```

> A *catalog* provider's key can also be pinned in config via `{env:KEY}` instead of `/connect`, if you'd rather keep setup in one file — but `/connect` is recommended: the key stays out of your config and host environment.

### Adding your own model instructions

Konrad ships its base instructions via the `instructions` config key. **For your own additions, use `AGENTS.md`**, which opencode discovers automatically and loads *on top of* the base:

- `~/.config/konrad/user/AGENTS.md` — your personal rules, loaded globally.
- `<workspace>/AGENTS.md` — per-project rules, loaded only in that workspace.

Both are additive. Don't set `instructions` in your override unless you specifically want to **replace** Konrad's base — arrays don't merge.

### For organizations

If you run a fleet of Konrad installs, the **org layer** (`~/.config/konrad/org/`) lets you ship defaults every user inherits — extra model declarations, an internal provider endpoint, house skills or agents, and a corporate `AGENTS.md` — without forking the image or hand-editing each user's config. It holds the same five pieces as the user layer and merges **between** the baked defaults and each user's own overrides (`baked < org < user`), so a user can still stack their preferences on top.

```
~/.config/konrad/org/
├── opencode.jsonc      Org-wide config (providers, models, env). Merged under user/.
├── agents/             House agents.
├── skills/             House skills.
├── AGENTS.md           Org instructions (loaded via the system instructions channel).
└── fonts/              Corporate fonts.
```

Two things worth knowing:

- **Discovery is a well-known home-directory folder, not a system path or env var.** Ship your config as a package that drops a folder into each user's `~/.config/konrad/org/`; Konrad finds it with no root, no `podman machine` mount edits, and no per-user setup. (This is what makes it work on macOS, where the Podman VM only auto-shares `$HOME`.)
- **`org/AGENTS.md` loads via the system `instructions` channel**, not as the discovered global `AGENTS.md` — that one stays the user's. Final instruction precedence is Konrad's `environment.md` → org → user `AGENTS.md` → project `AGENTS.md`, all additive.

**This is a defaults mechanism, not policy enforcement.** The org folder is just files in the user's own home directory, so a determined user can edit them. "Add-only" describes the merge *precedence* (the user stacks on top), not a permission lock. Locking config down would need read-only system locations or signing — a separate concern Konrad doesn't address today.

A ready-to-adapt starter package — a populated `org/` plus an `install.sh` that drops it into place — lives in [`examples/org-package/`](examples/org-package/). Design rationale (why a `$HOME` folder, why the system instructions channel, why defaults-not-enforcement) is in [ARCHITECTURE.md → Configuration & instructions](ARCHITECTURE.md#configuration--instructions).

## State

One rule: **`.agent/` belongs to the agent.** Framework state (opencode sessions, conversation DB, logs) lives outside the workspace so your project stays pristine.

| Where | What | Lifetime |
|---|---|---|
| `<workspace>/.agent/task.md` | Current task's plan + outcome | Overwritten next task; committable. |
| `<workspace>/.agent/artifacts/` | Durable mid-task outputs | Hands-off; committable. |
| `<workspace>/.agent/scratch/`, `.agent/quality-assurance/` | Agent scripts; verification evidence | Auto-pruned >7d; gitignored (added on first run). |
| `~/.local/state/konrad/log/` | opencode logs + per-launch session sidecar | Auto-pruned >7d; `ls -t` / `tail -f`. |
| Named volumes `konrad-secrets` / `-cache` / `-state` | Auth, cache, last-model + UI state | Shared across projects; wiped by `konrad --reset`. |

opencode's sessions and conversation DB are **ephemeral** — gone on container exit. Durable task memory is `.agent/task.md`, not the framework's history. Full rationale and the exact mount topology in [state isolation](ARCHITECTURE.md#state-secrets--isolation).

## Troubleshooting

| Symptom                                                          | Likely cause                                | Fix                                                                                       |
| ---------------------------------------------------------------- | ------------------------------------------- | ----------------------------------------------------------------------------------------- |
| `Cannot connect to Podman` / `connection refused`                | Podman VM not running (macOS)               | `podman machine init` (once), then `podman machine start`                                 |
| `LM Studio not reachable at http://localhost:1234`               | LM Studio off or on a wrong port            | LM Studio → Developer → Start Server, port 1234. (Or you're on Ollama / llama.cpp — set your model in [Configuration](#configuration) and ignore the warning.) |
| `EACCES: permission denied, mkdir '/home/node/.local/state'`     | Stale image (pre-permission-fix)            | `konrad --update`                                                                         |
| Agent can't find the file you mentioned                          | You ran `konrad` in the wrong directory     | The cwd is what gets mounted at `/workspace`. Always `cd` first.                          |
| `merge-config: failed to parse …/konrad/user/opencode.jsonc`     | Syntax error in your user override          | `cat` it and check the JSONC syntax. Comments are fine. (Same applies to `org/opencode.jsonc`.) |
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

- **Pinning & build cache** → [ARCHITECTURE.md → Build & reproducibility](ARCHITECTURE.md#build--reproducibility)
- **Versioning & release tags** → [CONTRIBUTING.md → Versioning](CONTRIBUTING.md#versioning)
- **State & isolation** → [ARCHITECTURE.md → State, secrets & isolation](ARCHITECTURE.md#state-secrets--isolation)
- **Planning contract (`task.md` + `todowrite`)** → [ARCHITECTURE.md → The planning contract](ARCHITECTURE.md#the-planning-contract)
- **Design decisions** → [ARCHITECTURE.md](ARCHITECTURE.md)
- **Repo layout, dev loop, contributing** → [CONTRIBUTING.md](CONTRIBUTING.md)

## License and attribution

Konrad is released under the [GNU Affero General Public License v3.0 or later](LICENSE). The combined work is AGPL-3.0-or-later; bundled third-party components keep their own (AGPL-compatible) licenses, declared per file following the [REUSE](https://reuse.software) specification — see [`REUSE.toml`](REUSE.toml) and [`LICENSES/`](LICENSES/) (`reuse lint`-verified).

**Acknowledgements.** Konrad is built on [opencode](https://github.com/sst/opencode) (MIT) and tuned for [Qwen3.6](https://huggingface.co/Qwen) (used via your provider, not bundled here). The agent prompt adapts patterns from [OpenAgentsControl](https://github.com/darrenhinde/OpenAgentsControl) and [opencode-froggy](https://github.com/smartfrog/opencode-froggy); the `pdf` skill's EXTRACT route builds on [docling](https://github.com/docling-project/docling).

---

<sub>The project is **Konrad** (it's a name); the command, image, and paths are `konrad`, lowercase — that's code.</sub>
