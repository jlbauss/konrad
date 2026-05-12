# konrad

A CLI wrapper around [opencode](https://github.com/sst/opencode) that runs it inside a sandboxed Podman container preloaded with skills and instructions. Aimed at making locally hosted agent models genuinely useful out of the box.

Status: **early / experimental**. The "safe" half of the original `safe-cowork` name (egress firewall, permission ACLs) is not yet implemented — see [BACKLOG.md](BACKLOG.md).

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

| Command           | What it does                                                 |
| ----------------- | ------------------------------------------------------------ |
| `konrad`          | Default. Runs opencode against the current directory.        |
| `konrad shell`    | Opens a bash shell in the container — same mounts, no agent. |
| `konrad rebuild`  | Rebuilds the `konrad:latest` image from this repo's `image/`.|
| `konrad clean`    | Removes the named volumes tied to the current directory.     |
| `konrad help`     | Show usage.                                                  |

### State and isolation

Each working directory gets its own set of named Podman volumes (`konrad-<hash>-opencode-data`, `-opencode-cache`, `-npm-global`), keyed by the absolute path. So:

- opencode session history, `/connect` auth, and autoupdated binaries persist across `konrad` invocations in the same folder,
- different test projects don't share state with each other or with the dev container,
- `konrad clean` from inside a project wipes only that project's state.

## Repo layout

```
konrad/
├── bin/konrad                 # The CLI
├── image/                     # Container build context — the canonical artifact
│   ├── Dockerfile
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

**Hacking on konrad itself.** Open this repo in VS Code with the Dev Containers extension and "Reopen in Container" — that path uses [.devcontainer/devcontainer.json](.devcontainer/devcontainer.json) and builds the image from `image/Dockerfile`. After any change to the Dockerfile or `image/opencode/`, run `konrad rebuild` (or `./scripts/build-image.sh`) to refresh the `konrad:latest` tag for the CLI side.

## License and attribution

konrad is released under the [GNU General Public License v3.0](LICENSE). The combined work as a whole is GPL v3; bundled third-party components retain their own (GPL-compatible) licenses. See [NOTICE](NOTICE) for the full upstream list:

- [opencode](https://github.com/sst/opencode) — MIT
- [planning-with-files](https://github.com/OthmanAdi/planning-with-files) by Othman Adi — MIT — source of the file-based planning methodology in `AGENTS.md`
- [MiniMax skills](https://huggingface.co/MiniMaxAI) (`minimax-pdf`, `minimax-docx`, `minimax-xlsx`, `gif-sticker-maker`, `frontend-dev`, `pptx-generator`, `fullstack-dev`) — MIT
- [Qwen3.6-35B-A3B](https://huggingface.co/Qwen/Qwen3.6-35B-A3B) weights — Apache 2.0 (used unmodified via LM Studio; not redistributed)
- Fonts under `frontend-dev/canvas-fonts/` — SIL Open Font License 1.1
