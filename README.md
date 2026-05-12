# konrad

A CLI wrapper around [opencode](https://github.com/sst/opencode) that runs it inside a sandboxed Podman container preloaded with skills and instructions. Aimed at making locally hosted agent models genuinely useful out of the box.

Status: **early / experimental**. The "safe" half of the original `safe-cowork` name (egress firewall, permission ACLs) is not yet implemented — see [ROADMAP.md](ROADMAP.md).

## What konrad gives you

- **A `konrad` CLI** you run from any folder on the host. It spins up the container with that folder mounted as the workspace, then drops you straight into opencode.
- **A Debian image** with curated tools (ripgrep, fd, jq, pandoc, ffmpeg, ImageMagick, tesseract, .NET 8, uv, playwright) so the agent doesn't have to install its own toolchain.
- **opencode** prewired to talk to LM Studio on the host.
- **Base instructions** ([AGENTS.md](image/opencode/AGENTS.md)) teaching the model file-based planning (`task_plan.md` / `progress.md` / `findings.md`), a 3-strike error protocol, and conventions for the bundled tools.
- **Seven domain skills** covering PDF, DOCX, XLSX, PPTX, GIF sticker generation, frontend, and full-stack work.

## Requirements

- **[Podman](https://podman.io/)** — Docker support is on the backlog. The image is run with `--userns=keep-id`, which is Podman-specific.
- **[LM Studio](https://lmstudio.ai/)** running on the host, with an OpenAI-compatible server on port `1234` and the [`qwen/qwen3.6-35b-a3b`](https://lmstudio.ai/models/qwen/qwen3.6-35b-a3b) model loaded.

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

That's the whole UX: the current directory is mounted at `/workspace` inside the container, opencode starts pointing at LM Studio, and you go.

### Subcommands

| Command              | What it does                                                          |
| -------------------- | --------------------------------------------------------------------- |
| `konrad`             | Default. Runs opencode against the current directory.                 |
| `konrad shell`       | Opens a bash shell in the container — same mounts, no agent.          |
| `konrad rebuild`     | Rebuilds the `konrad:latest` image from this repo's `image/`.         |
| `konrad clean`       | Removes this project's `.agent/opencode/` (sessions, cache).          |
| `konrad clean --all` | Also drops the shared volumes (auth, cache, npm). Forces fresh login. |
| `konrad version`     | Print CLI version and image info.                                     |
| `konrad help`        | Show usage.                                                           |

### State and isolation

konrad splits state across two tiers:

**Per-project, in the workspace.** When you run `konrad` in a directory, it creates `.agent/opencode/` inside that directory and bind-mounts it as opencode's data dir. Sessions, the SQLite database, and conversation logs live there — visible to `ls`, portable with your project, gitignored automatically. The model's working-memory files (`.agent/task_plan.md`, `.agent/progress.md`, `.agent/findings.md`) sit alongside them and are **not** gitignored, so you can commit them if you want a record.

**Shared, in named Podman volumes.** Three things stay out of the workspace and are shared across every project:

- `konrad-secrets` — `auth.json` (`/connect` credentials). You log in once, every project reuses it. Stays out of your filesystem and can't be committed by accident.
- `konrad-cache` — opencode's cache. Regeneratable; sharing means warm caches across projects.
- `konrad-npm-global` — the autoupdated opencode binary. One copy, all projects.

`konrad clean` removes the current project's `.agent/opencode/`. `konrad clean --all` *also* drops the shared volumes (next run requires a fresh `/connect`).

## Repo layout

```
konrad/
├── bin/konrad                 # The CLI
├── image/                     # Container build context — the canonical artifact
│   ├── Dockerfile
│   ├── entrypoint.sh          # Sets up the auth.json symlink before exec
│   └── opencode/              # Copied into ~/.config/opencode/ at build time
│       ├── AGENTS.md          # Base instructions for the model
│       ├── opencode.jsonc     # Provider, model, autoupdate
│       └── skills/            # Domain skills (pdf, docx, xlsx, pptx, etc.)
├── scripts/
│   ├── build-image.sh         # `podman build -t konrad:latest image/`
│   └── install.sh             # Symlinks bin/konrad into ~/.local/bin
└── .devcontainer/             # Optional: VS Code entry point for working ON konrad
    └── devcontainer.json
```

## Two ways to work with konrad

**Using konrad as a user.** Install once with the steps above. From then on, `cd` to whatever folder you want the agent to operate on and run `konrad`. The konrad repo only matters for getting the image and CLI installed; you don't open it day-to-day.

**Hacking on konrad itself.** Open this repo in VS Code with the Dev Containers extension and "Reopen in Container" — that path uses [.devcontainer/devcontainer.json](.devcontainer/devcontainer.json) and builds the image from `image/Dockerfile`. After any change to the Dockerfile or `image/opencode/`, run `konrad rebuild` (or `./scripts/build-image.sh`) to refresh the `konrad:latest` tag for the CLI side. See [CONTRIBUTING.md](CONTRIBUTING.md) for the development loop.

## Design decisions

A short, opinionated record of the load-bearing choices, so future-you can tell what's a constraint and what's a preference:

- **Podman, not Docker.** Open-source, free for commercial use, ergonomic on macOS. `--userns=keep-id` lets the container's `node` user share UID with the host user, so bind-mounted files have sane ownership. Docker support is in [ROADMAP.md](ROADMAP.md).
- **The image is the canonical artifact.** `image/Dockerfile` builds `konrad:latest`. Both `bin/konrad` and the optional `.devcontainer/devcontainer.json` are consumers of that one image.
- **Two-tier state.** Per-project workspace state in `.agent/opencode/` (visible, portable, gitignored); shared state (`auth.json`, cache, opencode binary) in named Podman volumes (out of the host filesystem, can't be committed by accident). The `auth.json`-symlink trick in `image/entrypoint.sh` is what makes these two halves coexist under one opencode data dir.
- **No per-project secrets in the workspace.** Auth credentials live only in the `konrad-secrets` named volume. Users who don't read `.gitignore` carefully still can't accidentally publish their tokens.
- **GPL v3.** Compatible with all bundled upstream licenses (MIT, Apache 2.0, OFL 1.1). Strong copyleft is a deliberate choice for a sandbox-style tool — if someone extends konrad for commercial use, the improvements come back to the commons.
- **LM Studio only, for now.** API-key providers are deferred ([ROADMAP.md](ROADMAP.md) → API key passthrough). Keeps the install story to "Podman + LM Studio" with no third surface area to manage.

## Troubleshooting

| Symptom                                                          | Likely cause                                | Fix                                                                                       |
| ---------------------------------------------------------------- | ------------------------------------------- | ----------------------------------------------------------------------------------------- |
| `Cannot connect to Podman` / `connection refused`                | Podman VM not running (macOS)               | `podman machine init` (once), then `podman machine start`                                 |
| `konrad: LM Studio not reachable at http://localhost:1234`       | LM Studio off or listening on a wrong port  | Open LM Studio → Developer → Start Server, port 1234                                      |
| `EACCES: permission denied, mkdir '/home/node/.local/state'`     | Stale image (pre-permission-fix)            | `konrad rebuild`                                                                          |
| Agent can't find the file you mentioned                          | You ran `konrad` in the wrong directory     | The cwd is what gets mounted at `/workspace`. Always `cd` first.                          |
| `konrad: warning: LM Studio not reachable …` but you started it  | Wrong host: `host.containers.internal`      | Inside container it's `host.containers.internal`; from the host it's `localhost`. The CLI checks the host side — make sure your host `curl localhost:1234/v1/models` returns JSON. |
| Want to wipe and start over                                      | —                                           | `konrad clean --all`, then `konrad rebuild`                                               |

If a problem isn't listed here, run `konrad shell` to poke around inside the container with the same mounts opencode would see.

## License and attribution

konrad is released under the [GNU General Public License v3.0](LICENSE). The combined work as a whole is GPL v3; bundled third-party components retain their own (GPL-compatible) licenses. See [NOTICE](NOTICE) for the full upstream list:

- [opencode](https://github.com/sst/opencode) — MIT
- [planning-with-files](https://github.com/OthmanAdi/planning-with-files) by Othman Adi — MIT — source of the file-based planning methodology in `AGENTS.md`
- [MiniMax skills](https://huggingface.co/MiniMaxAI) (`minimax-pdf`, `minimax-docx`, `minimax-xlsx`, `gif-sticker-maker`, `frontend-dev`, `pptx-generator`, `fullstack-dev`) — MIT
- [Qwen3.6-35B-A3B](https://huggingface.co/Qwen/Qwen3.6-35B-A3B) weights — Apache 2.0 (used unmodified via LM Studio; not redistributed)
- Fonts under `frontend-dev/canvas-fonts/` — SIL Open Font License 1.1
