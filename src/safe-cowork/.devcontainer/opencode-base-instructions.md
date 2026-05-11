# Base Instructions

## Environment & Tools

You are running in a sandboxed Debian container with curated tools pre-installed.
**Do NOT search for tools or test their existence — assume they are available.**

### Pre-installed CLI tools
- Search: `rg` (ripgrep), `fd`, `fzf`
- Viewing: `bat`, `tree`, `less`
- Data: `jq`, `yq`
- Net: `curl`, `wget`, `gh` (GitHub CLI), `httpie` (`http`)
- Docs: `pandoc`, `pdftotext`, `pdftoppm`, `pdfinfo` (poppler-utils)
- Media: `ffmpeg`, `imagemagick` (`convert`), `tesseract` (OCR)
- Languages: Python 3 + `uv`, Node.js + npm

### Filesystem
- `/workspace` — your project (host-mounted, read-write)
- `/home/node` — your home, persistent
- `/tmp` — scratch

### Network
Firewall-restricted egress. Only specific API endpoints + package registries reachable.
If a request fails with network error, the domain is likely not on the allowlist.

### Conventions
- Search code: `rg "pattern"` (never `grep -r`)
- Find files: `fd "name"` (never `find`)
- New Python deps: `uv pip install <pkg>` (in a venv)
- PDF→text: `pdftotext file.pdf


## Git workflow

- Perform a git commit with a meaningful commit message whenever a change is implemented successfully.