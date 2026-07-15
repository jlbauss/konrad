<div align="center">

# Konrad

**An open-source AI coworker that runs on your machine and your models — so even your most sensitive files stay yours.**

[![License: AGPL v3](https://img.shields.io/badge/license-AGPL--3.0-blue.svg)](LICENSE)
[![version](https://img.shields.io/badge/dynamic/yaml?url=https://gitlab.git.nrw/jbauss2/konrad/-/raw/main/VERSION&query=$&label=version&color=informational)](CHANGELOG.md)
[![status](https://img.shields.io/badge/status-beta-yellow)](#status)
[![image](https://img.shields.io/badge/image-ghcr.io%2Fjlbauss%2Fkonrad-blue)](https://github.com/users/jlbauss/packages/container/package/konrad)

</div>

Konrad is a coworking agent that lives on your computer. Like cloud coworking agents it reads, writes, and acts on real files for you — but it runs **your** models (a trustworthy API, or fully local) against your files inside a sandboxed container, so your most private data never leaves machines you trust. That opens up work the cloud agents can't touch: filling forms with sensitive personal details, processing private notes, handling regulated data.

Under the hood it's a thin wrapper around [opencode](https://github.com/sst/opencode): one container image with the agent and all its tools inside, and a small `konrad` CLI to run it.

## Why Konrad

- **Your data stays yours.** Run local models or a trustworthy API — handle the forms, private notes, and regulated data you'd never paste into a cloud chatbot.
- **Sandboxed by default.** The agent works inside a container that can't touch anything outside the workspace, and an egress firewall (on by default) restricts its network to an allow-list — your model providers plus a small trusted set — so a prompt-injected agent can't quietly ship your data off the box.
- **Your models, your choice.** Local engines (LM Studio / Ollama / llama.cpp) or any opencode-supported API provider — never locked to one vendor.
- **Batteries included.** One container image ships the agent's tools (ripgrep, fd, jq, pandoc, poppler, Python 3 + a system venv, Typst, LibreOffice) and a curated skill set already wired together: no venv, no pip, no host setup.
- **Fully open source.** AGPL-3.0, no telemetry, nothing proprietary.
- **Always current.** A bot tracks every upstream and CI rebuilds the image as they move; `konrad update` keeps you fresh. See [build & reproducibility](ARCHITECTURE.md#build--reproducibility).

What ships in the box:

- **Document skills**, loaded via opencode's `skill` tool: `pdf` (extract / edit / annotate / fill / generate), `spreadsheets` (xlsx / csv reading, editing, creation), and `image-editing` (resize, crop, convert, watermark, …).
- **Skills that keep results trustworthy:** `quality-assurance` (a verification cycle every producer skill runs before reporting a result) and `do-it-manually` (hands structured-but-irregular data to a careful manual-transformation subagent instead of debugging the Nth regex).
- **Helper skills:** `frontend-design` (polished web pages and components), `grill-me` (stress-tests your plan by interviewing you), and `write-a-skill` (scaffold your own skills). More on the way — see [ROADMAP.md](ROADMAP.md).
- **A planning contract** baked into the agent prompt: a single `.agent/task.md` per task with side effects, plus aggressive use of opencode's `todowrite` for live progress. Rationale in [the planning contract](ARCHITECTURE.md#the-planning-contract).
- **A curated font palette** — seven SIL OFL families (Inter, Source Serif 4, Fraunces, JetBrains Mono, EB Garamond, IBM Plex Sans, Atkinson Hyperlegible) plus Debian's Noto core for broad non-Latin coverage, so generated PDFs / slides / typeset docs look intentional out of the box. Drop your own into `~/.config/konrad/user/fonts/` to extend.

## Who it's for

Konrad is for someone who wants an AI agent to work on **their own files, on their own machine, with their own models** — especially when the data is too sensitive to send to a hosted service.

**It's probably not for you if you want:**

- **Coding / software development** — use Claude Code, Cursor, and the like; Konrad isn't tuned as a coding agent.
- **Research or web-heavy work** — deep-research and browsing agents do this better. Konrad has no browsing stack, and its default-on egress firewall deliberately narrows network access — it's built to stay on a leash, not to roam.
- **Production, hosted, or multi-user deployment** — it's a single-user local sandbox, not a deployable service.
- **A zero-config cloud agent** — if you just want a hosted frontier model with no setup, a first-party app is less friction. Konrad's payoff is local + your-files + sandbox.

## Quick start

Prerequisites once, then three steps: install, connect a model, run.

### Prerequisites

You need a container engine — Konrad auto-selects the right one for your OS:

| OS | Engine | One-time setup |
| --- | --- | --- |
| Linux | [Podman](https://podman.io/) | — |
| Apple-Silicon macOS 26+ | Apple's [`container`](https://github.com/apple/container) | `container system start` |
| Intel or older macOS | [Podman](https://podman.io/) | `podman machine init`, then `podman machine start` |

Optional: `git`, needed only for org-layer subscriptions — see [For organizations](#for-organizations).

(Docker support is on the roadmap, untested; Windows/WSL2 is untested and at your own discretion.)

### Install

Just paste this one-liner to your terminal:

```sh
curl -fsSL https://gitlab.git.nrw/jbauss2/konrad/-/raw/main/scripts/install.sh | sh
```

This drops `konrad` into `~/.local/bin/`, pre-pulls the container image, and warns if a prerequisite is missing or your `PATH` needs fixing. Re-run any time to upgrade in place.

### Connect a model

Any opencode-supported API provider (OpenRouter, Anthropic, OpenAI, Gemini, …) works out of the box — pick one and paste a key (or do the browser login):

```sh
konrad connect
```

Prefer a **local model**? [LM Studio](https://lmstudio.ai/) (`:1234`), [Ollama](https://ollama.com/) (`:11434`), and [llama.cpp](https://github.com/ggerganov/llama.cpp) (`:8080`) are pre-wired at their default ports — you only declare the model you've loaded (no auto-discovery yet). Recipe in [Set up a model provider](#set-up-a-model-provider).

**Recommended model class.** Konrad's skills and prompts are tuned for a **30B-class open-weight model with strong agentic ability** — we test against [`qwen/qwen3.6-27b`](https://huggingface.co/Qwen). Models should have **native vision**, a context window **≥ 256k**, and agentic strength at least on par with Qwen3.6 27B ([Artificial Analysis Agentic Index](https://artificialanalysis.ai/models/capabilities/agentic)); stronger models only help.

### Run it

```sh
cd ~/wherever-you-keep-the-files-the-agent-will-touch
konrad
```

That's the whole UX: the current directory is mounted at `/workspace` inside the container, opencode starts pointing at your configured model, and you go.

Working on Konrad itself? See [CONTRIBUTING.md](CONTRIBUTING.md) for the parallel `konrad-dev` CLI that tracks your checkout.

## Everyday use

### Subcommands

The action verbs are subcommands; `konrad` with no subcommand launches the TUI.

| Subcommand             | What it does                                                            |
| ---------------------- | ----------------------------------------------------------------------- |
| _(none)_               | Default. Launch the opencode TUI against the current directory.         |
| `run <args…>`          | Non-interactive: `opencode run <args…>` — one prompt, answer on stdout (pipeable). |
| `opencode <args…>`     | Pass-through to `opencode <args…>` in the sandbox — the escape hatch for opencode subcommands konrad doesn't wrap (`opencode models`, `agent list`, `session list`, …). |
| `shell`                | Open a bash shell in the container instead of the TUI.                  |
| `connect [args…]`      | Authenticate a provider (`opencode auth login`) — agent-free, firewall off. `connect --custom [id]` declares a self-hosted endpoint. |
| `mcp-auth <server>`    | Authenticate a remote MCP server's OAuth; the browser callback is forwarded into the sandbox. |
| `org add <git-url>`    | Subscribe to an organization's config layer (clones it to `~/.config/konrad/org/<name>/`; `--name`/`--branch` override the defaults). See [For organizations](#for-organizations). |
| `org` / `org list`     | List subscribed org layers (name, URL, tracked branch). |
| `org sync [<name>]`    | Re-sync all (or one) subscribed layers now — also happens on every `update`. |
| `org remove <name>`    | Delete an org layer. Prompts `[y/N]`. |
| `update`               | Refresh the CLI itself, pull the latest image from `ghcr.io/jlbauss/konrad:latest`, and re-sync subscribed org layers. `update --check` compares without pulling. |
| `reset`                | Wipe shared volumes + log dir. Prompts `[y/N]`; affects all workspaces. |
| `uninstall`            | Remove the CLI binary + the image. Prompts `[y/N]`. Leaves user config, shared volumes, and log dir alone. |

### Flags

Modifiers — pass them **before** the subcommand.

| Flag                     | What it does                                                            |
| ------------------------ | ----------------------------------------------------------------------- |
| `--no-firewall`          | Disable the egress firewall for this run (default ON). Restores unrestricted network access. |
| `--allow-host <host>`    | Add a host to the egress allow-list for this run (repeatable). Permanent entries go in `~/.config/konrad/user/allowed_hosts`. |
| `--profile <name>`       | Use throwaway state + cache volumes suffixed with `<name>` (credentials stay shared). |
| `-v`, `--verbose`        | Per-phase timestamps + a pointer to the opencode log file. Useful for chasing slow startup. |
| `--version`              | Print CLI + image versions, plus the immutable pin (short-sha), local tag, and build date. |
| `-h`, `--help`           | Show usage.                                                             |

`konrad-dev` is the contributor binary — same surface, except the `rebuild` subcommand replaces `update`. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Status

**Beta.** Konrad works day-to-day and the build/publish pipeline is solid, but the surface area is still pre-1.0 — and the agent edits real files, so keep backups of anything irreplaceable. What that means today:

- **Linux and macOS only, no Docker support yet.** Podman is the default; on macOS 26+ with Apple's [`container`](https://github.com/apple/container) CLI installed, Konrad uses that native engine instead — no `podman machine` VM. Docker support is on the roadmap, untested. No Windows support — WSL is at your own discretion and untested.
- **Pre-1.0: expect churn, but versioned.** Konrad uses [semantic versioning](CONTRIBUTING.md#versioning) — pre-1.0 that's `0.X.Y` (`X`/minor = new functionality or any user-visible change, `Y`/patch = fixes). The leading `0.` means config shapes, flags, and image internals can still change without a migration path; no stability promise until 1.0.
- **No unit-test suite.** Every published image passes a CI smoke gate (binaries, Python deps, baked content, a docling round-trip) and an end-to-end self-test exists for contributors, but there's no unit coverage — regressions on less-traveled paths can still slip through.
- **Local-model UX is still rough.** Tool-call parsing, context overflow, and model switching have known edges — the "works flawlessly on local models" shakedown is still a roadmap item. You must also hand-declare each loaded model (no auto-discovery yet).

## Configuration

Konrad composes opencode's runtime config from up to four layers at container start. **You only override what you want to change**; everything else stays inherited.

```text
Layer 1 — Baked defaults     /etc/konrad/opencode-defaults.jsonc   (in the image)
Layer 2 — Org layers         ~/.config/konrad/org/<name>/          (on the host, 0 or more)
Layer 3 — Your overrides     ~/.config/konrad/user/                (on the host)
Layer 4 — Per-project        <workspace>/.opencode/opencode.json   (opencode-native)
```

Each org layer and your user layer are symmetric — a directory with up to six optional pieces:

```text
~/.config/konrad/
├── org/                Optional. Subscribed org layers, one subdir each
│   └── <name>/         (see "For organizations") — same pieces as user/.
├── user/               Your personal layer.
│   ├── opencode.jsonc  Deep-merged with the baked default (and any org layer) at start.
│   ├── agents/         Your own primary agents, layered in.
│   ├── skills/         Your own opencode skills, layered in.
│   ├── instructions/   Any *.md here loads on top of Konrad's base instructions.
│   ├── AGENTS.md       Personal model instructions, loaded on top of Konrad's base.
│   ├── fonts/          .ttf / .otf / .ttc dropped here load on top of the baked palette.
│   └── allowed_hosts   Extra egress-firewall hosts, one per line (see Egress firewall).
└── context/            Optional. Read-only reference material (see "Reference material").
```

(The first five are opencode config, deep-merged at start. `allowed_hosts` is the one Konrad-specific extra — it feeds the egress firewall, not opencode. `context/` is separate again — not config, just files the agent reads; see [Reference material](#reference-material-the-context-mount).)

The merge of `opencode.jsonc` is deep and ordered **baked < org₁ < … < user** (org layers in alphabetical name order; last writer wins): **objects merge recursively, the later layer's keys win on conflict, new keys from any layer come through, arrays replace.** That last one matters — see [the AGENTS.md convention](#adding-your-own-model-instructions).

> **Upgrading from an early-alpha install?** The config layout changed twice during the alpha. Pre-0.4 kept your config flat at `~/.config/konrad/{opencode.jsonc,agents,…}` — move those into a `user/` subdir: `mkdir -p ~/.config/konrad/user && mv ~/.config/konrad/{opencode.jsonc,agents,skills,AGENTS.md,fonts} ~/.config/konrad/user/ 2>/dev/null`. Pre-0.18, `org/` _was_ a layer; it's now a container of named layers (Konrad warns at launch) — move it into a subdir (`cd ~/.config/konrad && mv org myorg && mkdir org && mv myorg org/`) or, better, resubscribe git-natively with `konrad org add <your org's repo URL>`.

### Set up a model provider

**The standard way is `/connect`.** Launch `konrad`, run `/connect` in the TUI, pick your provider (OpenRouter, Anthropic, OpenAI, Gemini, …) and paste a key — or do the browser login. opencode stores the credential in the `konrad-secrets` volume (`auth.json`), never in your config or host environment; it lists that provider's models in the picker (from the bundled [models.dev](https://models.dev) catalog — nothing to declare); and the egress firewall allows the provider automatically, live-reloading mid-session. No file editing.

Prefer to authenticate without launching the TUI — or doing an **OAuth** login (Claude Pro/Max, Copilot)? Run **`konrad connect`** (`konrad connect -p <provider>` to skip the picker). It runs `opencode auth login` with no agent in the loop and the firewall off, so even an OAuth first-connect needs no `--allow-host` (see [Egress firewall](#egress-firewall)).

Editing `opencode.jsonc` is only needed to:

- **declare a local model** — the local engines (LM Studio / Ollama / llama.cpp) are pre-wired at their default ports, but there's no model auto-discovery yet (an inline replacement is on the [roadmap](ROADMAP.md)), so you list what you've loaded (recipe below).
- **add a custom / self-hosted endpoint** — anything not in the models.dev catalog needs an explicit `baseURL` (recipe below).

opencode Zen — the upstream's paid hosted gateway — is **disabled by default** (`disabled_providers: ["opencode"]`). Override `disabled_providers` to re-enable.

### Egress firewall

The agent runs on an isolated container network with **no direct route to the internet**. A sidecar — the same Konrad image launched as a filtering proxy — is the only thing with egress, and it forwards traffic only to an allow-list, refusing everything else (default-deny). This shrinks the blast radius if the agent is prompt-injected: it can't quietly POST your workspace or credentials to an arbitrary host.

The allow-list is assembled at launch from:

- **your model providers**, derived automatically — both the ones you **declare** in `opencode.jsonc` (local `host.containers.internal` and any remote API host alike) and the built-in ones you **connect** with `/connect` (OpenRouter, Anthropic, OpenAI, …). Built-in providers carry no URL in your config, so Konrad resolves them to a host via a baked map generated from [models.dev](https://models.dev). Connecting a provider mid-session just works — the firewall live-reloads within a couple of seconds, no restart needed;
- **`registry.npmjs.org`**, where opencode fetches a provider's SDK adapter on demand (the OpenAI-compatible adapter that backs the local engines is already bundled; Anthropic/Google-style SDKs are pulled on first use);
- **your own additions** — list hosts (one per line, `#` comments) in `~/.config/konrad/user/allowed_hosts` (or the org layer's), or pass `--allow-host <host>` for a single run.

> One edge: an **OAuth** login (e.g. Claude Pro/Max) does its handshake _before_ the credential is saved, so that first connect can't be auto-allowed mid-session. The clean path is **`konrad connect`** — it authenticates with the firewall off (safe: no agent is running), so no `--allow-host` is needed. (Doing it inside a normal session instead? Pass `--allow-host <provider-host>` once, or `--no-firewall`.) API-key providers have no such step.
>
> The boundary covers **your own machine too**, on both engines. Rootless Podman has no route from the sandbox to the host. Apple's `container` is different under the hood — its isolated network is "host-only", so its gateway sits on your Mac — so Konrad explicitly **seals** that route: the agent starts with just enough privilege to blackhole the gateway, then drops it, leaving the agent unable to reach host services directly. The only way to your machine, on either engine, is the same proxy + allow-list everything else goes through — which is exactly how a **local model** at `host.containers.internal` stays reachable while nothing else on the host is.

Deliberately **not** in the default set: `models.dev` (the external model catalog — opencode bundles a snapshot and Konrad bakes the provider-host map from it, so the live site isn't needed at runtime), PyPI (`pip install` — the image already ships a full venv; `--allow-host pypi.org files.pythonhosted.org` when you genuinely need to extend it), and the open web. Add what your task needs.

It's **on by default**. Turn it off for a run with `konrad --no-firewall`. When the agent reports a host is blocked, that's the firewall doing its job — add the host if you trust it. (Why a proxy and not a raw IP block: remote providers sit behind rotating cloud IPs, so the allow-list is by _hostname_. Full design in [ARCHITECTURE.md](ARCHITECTURE.md#state-secrets--isolation).)

**The firewall is the containment boundary — not a secret read-gate.** Your provider credential lives on-disk in the `konrad-secrets` volume, and a prompt-injected agent can read it or copy it into `/workspace`; what stops it _leaving the box_ is this default-deny firewall, not a read restriction. So `--no-firewall` (or opening `--allow-host` to a host you don't trust) removes that containment for the run — use it only when you trust the agent and the task.

### Resource limits

Each run caps the agent container's RAM and CPU, on both engines, at a ceiling **auto-scaled to your machine** — half the host RAM (clamped to `2`–`8 GB`) and all but two of the cores (clamped to `2`–`8`). This bounds a runaway or fork-bombing agent and keeps konrad from crowding a co-resident local model on a big machine (`docling` fits comfortably in both ceilings; raise them for heavy OCR), and — on Apple's `container`, whose per-container default is a tight 1 GB — it lifts a ceiling small enough to get the bundled `docling` models OOM-killed mid-run. The CPU cap doubles as the container's thread budget (`OMP_NUM_THREADS`), so `docling` PDF extraction actually uses your cores instead of self-throttling to 4 threads. `konrad --help` prints the values computed for your host.

Pin explicit values (or opt out) per run with environment variables:

```sh
KONRAD_MEMORY=8G konrad        # pin the RAM cap (heavy docling / OCR on large scans)
KONRAD_CPUS=8 konrad           # pin the CPU-core cap (also docling/torch's thread count)
KONRAD_MEMORY=0 konrad         # no RAM cap (Podman's previous unbounded behaviour)
KONRAD_PIDS_LIMIT=4096 konrad  # raise the task/thread cap (Podman; 0 disables, default 1024)
```

On Podman, the container is further hardened at the kernel: it starts with **every Linux capability dropped**, `no-new-privileges` set (no privilege escalation via setuid binaries), and a **task-count cap** (`--pids-limit`, default `1024`) so a fork bomb can't exhaust the host's PID space. Raise the last with `KONRAD_PIDS_LIMIT` if a heavy `docling`/OCR run ever exhausts its thread budget. On Apple's `container` these are already bounded by its per-container VM boundary.

### Edit your override

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

(On Apple `container`, the `podman run` one-liners don't apply — open `konrad shell` and copy `/etc/konrad/opencode-defaults.jsonc` from inside.)

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

> A _catalog_ provider's key can also be pinned in config via `{env:KEY}` instead of `/connect`, if you'd rather keep setup in one file — but `/connect` is recommended: the key stays out of your config and host environment.

### Adding your own model instructions

Two additive ways to add your own, both loaded _on top of_ Konrad's base — pick by where you want them to apply:

- **`AGENTS.md`** — opencode discovers these automatically:
  - `~/.config/konrad/user/AGENTS.md` — your personal rules, loaded globally.
  - `<workspace>/AGENTS.md` — per-project rules, loaded only in that workspace.
- **`~/.config/konrad/user/instructions/*.md`** — drop any number of `.md` files here and each is appended to the system instructions. Same channel as Konrad's own base (each org layer has the matching `org/<name>/instructions/`); handy for splitting rules across several files or shipping a generated one.

All additive — nothing replaces Konrad's base. You don't need to (and shouldn't) set the `instructions` array in your `opencode.jsonc`: it's an array, so it would **replace** the layered defaults wholesale rather than add to them. Drop a file in `instructions/` instead.

### Reference material (the `context/` mount)

Drop reference material — a mirrored wiki, internal docs, lookup tables — into `~/.config/konrad/context/<name>/` and Konrad bind-mounts the whole `context/` directory **read-only** at `/context` inside the sandbox (so the example lands at `/context/<name>/`). The agent can then `grep`/`rg` it while it works, with **no network and no stored secret** — ideal for material too private or too large to paste into a prompt. The mount appears only when the directory exists; populate it by hand or point a sync script at it.

This is _not_ a config layer — it takes no part in the `baked < org < user` merge; it's just files the agent reads. To make the agent actually _reach_ for a corpus, name it in your `AGENTS.md` ("ASG processes are documented in `/context/asg-wiki/`"), or ship a small skill that points at the mount for richer, triggered guidance. `konrad reset`/`uninstall` leave `context/` alone — it's your material.

### For organizations

If you run a fleet of Konrad installs, an **org layer** lets you ship defaults every user inherits — extra model declarations, an internal provider endpoint, house skills or agents, and house instructions — without forking the image or hand-editing each user's config. An org layer is simply **a git repository whose tree is the layer**; each member subscribes once:

```sh
konrad org add https://git.example.com/acme/konrad-org
```

That clones the repo to `~/.config/konrad/org/<name>/` (name from the repo basename, tracked branch from the remote default; `--name` / `--branch` override). From then on **every `konrad update` re-syncs it** — shipping a change to the fleet is just `git push`. Each layer holds the same pieces as the user layer and merges **between** the baked defaults and each user's own overrides (`baked < org < user`), so a user can still stack their preferences on top:

```text
~/.config/konrad/org/<name>/
├── opencode.jsonc      Org-wide config (providers, models, env). Merged under user/.
├── agents/             House agents.
├── skills/             House skills.
├── instructions/       Any *.md here is appended to the system instructions.
├── AGENTS.md           Org instructions (back-compat; prefer instructions/).
├── fonts/              Corporate fonts.
├── allowed_hosts       Extra egress-firewall hosts, one per line.
└── hooks/post-sync     Optional host-side hook — see the trust note below.
```

Worth knowing:

- **A subscribed layer is a managed mirror.** `konrad org sync` (and every `update`) does a fetch + hard reset to the tracked branch, so local edits inside the layer are clobbered — a user's own channel stays the `user/` layer, which always merges on top. A failed sync warns and keeps the last-good checkout. Checking out a tag pins the layer (no upstream branch → sync skips it). `konrad org list` shows what's subscribed; there's no state file — the checkout's own `.git` records URL and branch.
- **Private repos need no Konrad-side auth.** Syncing runs your host `git`, so whatever already works for you — a forge CLI login (`gh auth login` / `glab auth login`, which also installs a git credential helper) or SSH — just applies. Konrad ships zero auth code.
- **`hooks/post-sync` runs org code on the member's machine — subscribing is trusting.** If the layer ships an executable `hooks/post-sync`, Konrad runs it after `org add` and after every successful sync (cwd = the layer dir, output streamed). It's the escape hatch for the few jobs plain config can't express: mirroring a wiki into `~/.config/konrad/context/` (see [Reference material](#reference-material-the-context-mount)), deriving per-member identity from your forge CLI. Because it rides the branch, it self-updates with the rest of the layer. There is no sandbox and no prompt around it — **only subscribe to repos you trust**, exactly as with any `curl | sh` internal tooling.
- **Multiple layers compose.** Every `org/<name>/` merges, in alphabetical name order (control precedence with a numeric prefix: `10-core`, `20-team`), each still below the user layer. A plain non-git directory is a valid manual layer too — it just never syncs.
- **Discovery is a well-known home-directory folder, not a system path or env var.** Konrad finds the layers with no root, no `podman machine` mount edits, and no per-user setup. (This is what makes it work on macOS, where the Podman VM only auto-shares `$HOME`.)
- **Org instructions ride the system `instructions` channel**, not the discovered global `AGENTS.md` — that one stays the user's. Drop any number of `.md` files into the layer's `instructions/` (the post-sync hook can generate one too); each is appended additively. A layer-root `AGENTS.md` still works as a single-file back-compat alias. Final instruction precedence is Konrad's `environment.md` → org → user `AGENTS.md` → project `AGENTS.md`, all additive.

**This is a defaults mechanism, not policy enforcement.** The org layers are just files in the user's own home directory, so a determined user can edit them (until the next sync) or unsubscribe. "Add-only" describes the merge _precedence_ (the user stacks on top), not a permission lock. Locking config down would need read-only system locations or signing — a separate concern Konrad doesn't address today.

A ready-to-publish starter repo — sample config, instructions, a house skill, and an example `hooks/post-sync` — lives in [`examples/org-package/`](examples/org-package/). Design rationale (why git-native mirrors, why a `$HOME` folder, why the host-side hook, why defaults-not-enforcement) is in [ARCHITECTURE.md → Configuration & instructions](ARCHITECTURE.md#configuration--instructions).

### Environment variables (advanced)

Rarely needed — the flags cover day-to-day use. Collected here so the rest of the docs stays clean:

| Variable | Effect |
| --- | --- |
| `KONRAD_ENGINE` | Pin the container engine (`podman` or `container`) instead of the per-OS auto-selection. |
| `KONRAD_FIREWALL=0` | Disable the egress firewall (same as `--no-firewall`). |
| `KONRAD_IMAGE` | Run a specific image tag (e.g. a PR test build) instead of the default. |
| `KONRAD_MEMORY` / `KONRAD_CPUS` / `KONRAD_PIDS_LIMIT` | Pin or disable the resource caps — see [Resource limits](#resource-limits). |
| `KONRAD_INSTALL_DIR` | Installer: where to put the CLI (default `~/.local/bin`). |
| `KONRAD_NO_PULL=1` | Installer: skip the image pre-pull. |
| `KONRAD_DEBUG=1` / `KONRAD_TRACE_FETCH=1` | Verbose launch / raw HTTP trace — see [Debugging opencode](#debugging-opencode). |

## State

One rule: **`.agent/` belongs to the agent.** Framework state (opencode sessions, conversation DB, logs) lives outside the workspace so your project stays pristine.

| Where | What | Lifetime |
|---|---|---|
| `<workspace>/.agent/task.md` | Current task's plan + outcome | Overwritten next task; committable. |
| `<workspace>/.agent/artifacts/` | Durable mid-task outputs | Hands-off; committable. |
| `<workspace>/.agent/scratch/`, `.agent/quality-assurance/` | Agent scripts; verification evidence | Created by the agent on demand; konrad neither creates, prunes, nor gitignores them — they're yours to manage. |
| `~/.local/state/konrad/log/` | opencode logs | Auto-pruned >7d; `ls -t` / `tail -f`. |
| Named volumes `konrad-secrets` / `-cache` / `-state` | Auth, cache, last-model + UI state | Shared across projects; wiped by `konrad reset`. |

opencode's sessions and conversation DB are **ephemeral** — gone on container exit. Durable task memory is `.agent/task.md`, not the framework's history. Full rationale and the exact mount topology in [state isolation](ARCHITECTURE.md#state-secrets--isolation).

## Troubleshooting

| Symptom                                                          | Likely cause                                | Fix                                                                                       |
| ---------------------------------------------------------------- | ------------------------------------------- | ----------------------------------------------------------------------------------------- |
| `Cannot connect to Podman` / `connection refused`                | Podman VM not running (macOS)               | `podman machine init` (once), then `podman machine start`                                 |
| `cannot reach Apple's container service`                         | Apple `container` not started (macOS)       | `container system start` (or `KONRAD_ENGINE=podman` to use Podman instead)                |
| A local model errors or never answers                            | Engine not serving, or model not declared   | Start the engine's server on its default port (LM Studio `:1234` via Developer → Start Server, Ollama `:11434`, llama.cpp `:8080`) and declare the loaded model — see [Configuration](#configuration). |
| Agent can't find the file you mentioned                          | You ran `konrad` in the wrong directory     | The cwd is what gets mounted at `/workspace`. Always `cd` first.                          |
| `refusing to run with your home directory as the workspace`      | You ran `konrad` straight from `$HOME`      | `cd` into a project directory first — konrad mounts the cwd as `/workspace`, and `$HOME` exposes everything (and fails to mount on SELinux / macOS). |
| A command (e.g. `docling`) prints `Killed` with no error         | Container hit its RAM cap (out-of-memory)   | Raise it for the run: `KONRAD_MEMORY=8G konrad` (see [Resource limits](#resource-limits)). |
| `merge-config: failed to parse …/konrad/user/opencode.jsonc`     | Syntax error in your user override          | `cat` it and check the JSONC syntax. Comments are fine. (Same applies to an org layer's `org/<name>/opencode.jsonc`.) |
| Want to wipe and start over                                      | —                                           | `konrad reset` (prompts `[y/N]`), then `konrad update`                                |

If a problem isn't listed here, run `konrad shell` to poke around inside the container with the same mounts opencode would see.

### Debugging opencode

opencode writes a fresh, timestamped log on every launch; Konrad bind-mounts it to **`~/.local/state/konrad/log/`** (standard XDG state).

```sh
ls -t ~/.local/state/konrad/log/                                  # newest first
tail -f ~/.local/state/konrad/log/$(ls -t ~/.local/state/konrad/log/*.log | head -1)
```

For deeper digging, pass `-v` / `--verbose` (or export `KONRAD_DEBUG=1`): per-phase timestamps plus a pointer to the log file. For a raw trace of every HTTP call, additionally export `KONRAD_TRACE_FETCH=1` (it enables Bun's verbose fetch logging, written to the same log). If startup is slow, the usual suspects and the env vars that disable each (set them via the merged config's `env` key):

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

**Acknowledgements.** Konrad is built on [opencode](https://github.com/sst/opencode) (MIT) and tuned for [Qwen3.6](https://huggingface.co/Qwen) (used via your provider, not bundled here). The agent prompt adapts patterns from [OpenAgentsControl](https://github.com/darrenhinde/OpenAgentsControl) and [opencode-froggy](https://github.com/smartfrog/opencode-froggy); the `pdf` skill's EXTRACT route builds on [docling](https://github.com/docling-project/docling); the bundled skills adapt work by [Anthropic](https://github.com/anthropics/skills) and [Matt Pocock](https://github.com/mattpocock) (see each skill's header for its license).

---

<sub>The project is **Konrad** (it's a name); the command, image, and paths are `konrad`, lowercase — that's code.</sub>
