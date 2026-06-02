# ACME house rules (example org instructions)

This file ships in the org layer at `~/.config/konrad/org/AGENTS.md`. konrad's
entrypoint loads it via opencode's **system `instructions` channel** (appended
after the config merge), so it applies fleet-wide and is additive — it never
replaces konrad's baked instructions or the user's own `AGENTS.md`.

Replace everything below with your organization's actual conventions.

## Example conventions

- Default to ACME's internal gateway (`acme-internal/acme-qwen3-coder`) for code
  work unless the user picks another model.
- Internal hostnames live under `*.acme.example`; never send code or secrets to
  third-party endpoints that aren't on the approved list.
- When generating documents, use the ACME letterhead conventions and the
  corporate fonts shipped in this package's `fonts/` directory (if present).
- Cite the internal wiki by its short code (e.g. `WIKI-1234`), not a full URL.
