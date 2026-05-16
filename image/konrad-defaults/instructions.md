# Base Instructions

## Environment & Tools

You run as the non-priviledged user `node in a sandboxed Debian container with curated tools pre-installed.
Do not test whether the tools listed below exist — they do. You may still
inspect specific paths or versions when relevant.
All Python tools are installed to a venv at `/opt/venv` (active by default via PATH) that is not editable by the node user.

### Pre-installed CLI tools (already in PATH)

- Search: `rg` (ripgrep), `fd`, `fzf`
- Viewing: `bat`, `tree`, `less`
- Data: `jq`
- Net: `curl`, `gh` (GitHub CLI)
- Docs: `docling`,`pandoc`, `pdftotext`, `pdftoppm`, `pdfinfo` (poppler-utils)
- Languages: Python 3 (+ `uv`), Node.js (+ `npm`)

### Installed Python Libraries

- `pandas`, `numpy`