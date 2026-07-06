# ACME house rules (example org instructions)

This file ships in the org layer at
`~/.config/konrad/org/<name>/instructions/house-rules.md`. konrad loads every
`*.md` under a layer's `instructions/` dir onto opencode's **system
`instructions` channel**, so it applies fleet-wide and is additive — it never
replaces konrad's baked instructions or the user's own `AGENTS.md`. Add as many
files here as you like (the post-sync hook can drop a generated one too, e.g.
per-member identity). A single `AGENTS.md` at the layer root still works as a
back-compat alias, but new orgs should prefer this dir.

Replace everything below with your organization's actual conventions.

## Example conventions

- Default to ACME's internal gateway (`acme-internal/acme-qwen3-coder`) for code
  work unless the user picks another model.
- Internal hostnames live under `*.acme.example`; never send code or secrets to
  third-party endpoints that aren't on the approved list.
- When generating documents, use the ACME letterhead conventions and the
  corporate fonts shipped in this package's `fonts/` directory (if present).
- Cite the internal wiki by its short code (e.g. `WIKI-1234`), not a full URL.
