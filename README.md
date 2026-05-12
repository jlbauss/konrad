# konrad

A sandboxed [opencode](https://github.com/sst/opencode) devcontainer preloaded with skills and instructions, aimed at making locally hosted agent models genuinely useful out of the box.

Status: **early / experimental**. The "safe" half of the original `safe-cowork` name (egress firewall, permission ACLs) is not yet implemented — see [BACKLOG.md](BACKLOG.md).

## What konrad gives you

- **A Debian devcontainer** with curated CLI tools (ripgrep, fd, jq, pandoc, ffmpeg, ImageMagick, tesseract, .NET 8, uv, playwright) so the agent doesn't have to install its own toolchain.
- **opencode** prewired to talk to LM Studio on the host.
- **A base instruction file** (`AGENTS.md`) that teaches the model file-based planning (`task_plan.md` / `progress.md` / `findings.md`), a 3-strike error protocol, and conventions for the bundled tools.
- **Seven domain skills** covering PDF, DOCX, XLSX, PPTX, GIF sticker generation, frontend, and full-stack work.

## Requirements

- **[Podman](https://podman.io/)** — Docker support is on the backlog. The devcontainer's `runArgs` use `--userns=keep-id`, which is Podman-specific.
- **[LM Studio](https://lmstudio.ai/)** running on the host, with an OpenAI-compatible server on port `1234` and the [`qwen/qwen3.6-35b-a3b`](https://lmstudio.ai/models/qwen/qwen3.6-35b-a3b) model loaded.
- A devcontainer-aware editor (VS Code with Dev Containers, or `devcontainer` CLI).

## Quick start

1. Start LM Studio on the host, load `qwen/qwen3.6-35b-a3b`, enable the local server.
2. Open this repo in your devcontainer-aware editor and **Reopen in Container**.
3. On first start, the container will print whether LM Studio is reachable. If not, fix the host side and rebuild — the container won't be useful without it.
4. Inside the container: `opencode` to start.

## Repo layout

```
src/konrad/.devcontainer/
├── Dockerfile          # The container image
├── devcontainer.json   # Mount, user, lifecycle config
└── opencode/           # Copied into ~/.config/opencode/ at build time
    ├── AGENTS.md       # Base instructions for the model
    ├── opencode.jsonc  # Provider, model, autoupdate
    └── skills/         # Domain skills (pdf, docx, xlsx, pptx, etc.)
```

## Why a named volume for opencode state

The devcontainer mounts a named volume at `/home/node/.local/share/opencode` (and a few neighbours). Without it, **every container rebuild wipes**:

- opencode session history and `/connect` provider state,
- the autoupdated opencode binary in `~/.npm-global/`,
- the model's planning files if it happened to write them to `$HOME` instead of `/workspace`.

A named volume keeps those across rebuilds without coupling them to a specific host path. The mounted `/workspace` is still where your project work lives — it's bind-mounted from the host as before.

## License and attribution

konrad is released under the [MIT License](LICENSE). It bundles or builds on:

- [opencode](https://github.com/sst/opencode) — MIT
- [planning-with-files](https://github.com/OthmanAdi/planning-with-files) by Othman Adi — MIT — the source of the file-based planning methodology in `AGENTS.md`
- [MiniMax skills](https://huggingface.co/MiniMaxAI) (`minimax-pdf`, `minimax-docx`, `minimax-xlsx`, `gif-sticker-maker`, `frontend-dev`, `pptx-generator`, `fullstack-dev`) — MIT (see each skill's frontmatter / `LICENSE`)
- [Qwen3.6-35B-A3B](https://huggingface.co/Qwen/Qwen3.6-35B-A3B) weights — Apache 2.0 (used unmodified via LM Studio; not redistributed in this repo)

All bundled components ship under MIT-compatible terms.
