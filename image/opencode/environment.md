# Konrad runtime environment

You run as `node` (uid 1000) in a sandboxed Debian container. The tools
listed below are pre-installed — don't probe to check whether they exist.

## Filesystem

| Path | What |
|---|---|
| `/workspace` | User's project, bind-mounted. Default cwd. |
| `/workspace/.agent/` | Your durable working memory (`task.md`, `scratch/`, `artifacts/`, `quality-assurance/` — see agent prompt). |
| `/opt/venv` | Python venv, active via `PATH`. Read-only; use `uv pip install --user` for session adds. |
| `/home/node/.config/opencode/` | opencode runtime config (agents, skills, this file). |
| `/home/node/.config/konrad/` | Optional user overlays bind-mounted from the host. |
| `/tmp` | Truly ephemeral; dies with the container. |

To persist past container exit: `/workspace/.agent/artifacts/` (kept)
or `/workspace/.agent/scratch/` (auto-pruned >7d). Don't write to the
workspace root unless the user asked for it there.

## CLI tools on PATH

- Search / fs: `rg` `fd` `fzf` `tree`
- View: `bat` `less`
- Data: `jq`
- Git / GitHub: `git` `gh`
- Network: `curl` (reach the host machine at `host.containers.internal` — local-model providers live there)
- Documents: `docling` `docling-tools` `pdftotext` `pdftoppm` `pdfinfo` `pdfimages` `pandoc` `libreoffice` (headless) `typst`
- Languages: `python3` `node` `npm` `uv` `uvx`
- From the venv: `hf` (huggingface-cli)

Two Debian binaries are renamed; symlinks under canonical names exist:
`fd` → `/usr/bin/fdfind`, `bat` → `/usr/bin/batcat`. Both names work.

## Python venv

Active by default. Top-level deps: `docling-slim[standard]`, `pypdf`,
`pdfplumber`, `pdf2image`, `reportlab`, `openpyxl`, `pandas`,
`onnxruntime`, `pillow-heif` (HEIC/HEIF support for the image-editing
skill — `pillow` and `numpy` come along, used directly by that skill's
CLI). Transitives include the usual suspects (`numpy`, `scipy`,
`pillow`, `requests`, `httpx`, `beautifulsoup4`, `lxml`, `pydantic`,
`rich`, `huggingface-hub`, `transformers`, `torch` cpu, `python-docx`,
`python-pptx`, `xlsxwriter`, `pypdfium2`, `pdfminer.six`). Full pinned
set: `image/locks/python.lock`. Skill scripts under
`~/.config/opencode/skills/*/scripts/` rely on the venv being active.

## Locale

`LANG=C.UTF-8`, `LC_ALL=C.UTF-8`. Python's `open()`, awk, sort all
default to UTF-8 — if you see mojibake, the source's encoding is the
cause, not the runtime.

## Network

Egress is **default-deny** behind a filtering proxy (`HTTP_PROXY`/`HTTPS_PROXY`
are set for you — honour them). Reachable by default: the configured model
providers, plus `registry.npmjs.org`. Everything else is refused — including
`models.dev`, PyPI (`pip install`), and arbitrary web/git hosts.

So if a `curl`/`pip install`/`git`/fetch fails with a connection-refused or
`403` proxy error, the host is almost certainly **blocked, not down** — do NOT
retry in a loop (it wastes turns and tokens). Tell the user the host is blocked
and that they can allow it for a run with `konrad --allow-host <host>` (e.g.
`--allow-host pypi.org --allow-host files.pythonhosted.org` for `pip`), or
permanently via an `allowed_hosts` file in their konrad config layer (one host
per line). The whole firewall turns off for a run with `konrad --no-firewall`.

## What you DON'T have

- Root or `sudo`.
- `apt install` access — to add a system package the user edits
  `image/Dockerfile` and rebuilds.
- Persistent Python installs — `uv pip install --user` dies with the
  container; for persistence the user adds to `image/locks/python.spec`.
