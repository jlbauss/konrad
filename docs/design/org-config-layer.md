# Org config layer — a third layer between baked defaults and per-user config

Status: accepted 2026-06-02. Implements the ROADMAP "Org config layer" item
(Tier 1). Ships in 0.4.0.

This note records *why* the org layer is shaped the way it is. The mechanism
itself lives in [bin/konrad](../../bin/konrad) (host-side discovery, migration,
mounts) and [image/entrypoint.sh](../../image/entrypoint.sh) (the merge +
instruction wiring); when those disagree with this note, they are canonical and
the note is stale — update it.

## What this adds

Before 0.4.0, konrad config was two layers: the baked image defaults
(`/etc/konrad/opencode-defaults.jsonc` plus the baked `agents/` / `skills/` /
`environment.md`) and a single per-user override directory at
`~/.config/konrad/`. An organization provisioning a fleet — extra model
declarations, an internal provider endpoint, house skills, a corporate
`AGENTS.md` — had no clean slot between the two. The only options were to
hand-edit every user's config (doesn't scale, gets clobbered the moment a user
edits their own) or fork the image (heavy, and now you own a rebuild pipeline).

The org layer is a **third layer between baked defaults and per-user config**,
merged **baked < org < user** (last writer wins). An org ships its defaults; a
user still stacks their own preferences on top.

## The four locked decisions

### 1. Discovery is a well-known `$HOME` folder — not an env var, not a system path

The org layer lives at `~/.config/konrad/org/`, auto-detected. No
`KONRAD_ORG_CONFIG` env var, no `/etc`-style system path.

The driver is macOS, the main target. konrad runs its container under a Podman
machine (a Linux VM), and that VM only auto-shares the user's `$HOME` into
itself. A `/etc/konrad/org/` on the macOS host would simply be invisible to the
container — it isn't on a shared path — so a system location would require every
admin to edit `podman machine` mount configuration. A `$HOME` folder needs no
root, no VM mount edits, and no per-user setup beyond dropping the folder in
place. An org ships its config as a package whose installer writes
`~/.config/konrad/org/`; konrad finds it.

A `KONRAD_ORG_CONFIG` override (point the org layer somewhere else) is
intentionally **deferred**. It's trivial to add later if a fleet needs a
non-default location, and shipping it now would be speculative surface.

### 2. Layout is two symmetric layer dirs: `org/` and `user/`

`~/.config/konrad/` splits into `~/.config/konrad/org/` (new) and
`~/.config/konrad/user/` (the per-user layer, **relocated** here from the old
flat `~/.config/konrad/*`). Each dir holds the same five things —
`opencode.jsonc`, `skills/`, `agents/`, `AGENTS.md`, `fonts/` — full parity, so
there's one mental model for both layers.

The symmetry also kills a footgun: a user who wants to reset their config resets
`user/`, not the whole tree, so they can't accidentally wipe an org's contribution.

### 3. Transition is auto-migration

`bin/konrad` is host-side and live (not baked into the image), so it can fix up
the on-disk layout before launch. `migrate_flat_config()` detects a flat
`~/.config/konrad/{opencode.jsonc,agents,skills,AGENTS.md,fonts}` layout and, if
`user/` doesn't yet exist, `mv`s those items into `user/` with a one-time
"moved your config into ~/.config/konrad/user/" notice. It is idempotent — it
runs only when `user/` is absent *and* at least one flat item is present, so a
fresh install and an already-migrated install both no-op.

This is a pre-1.0 breaking change to the config path, accepted because the
blast radius is ~nil (the repo is still pre-public) and the migration is
automatic.

### 4. Org instructions ride the system `instructions` channel

`org/AGENTS.md` loads via opencode's `instructions` array — the same channel as
the baked `environment.md` — **not** as the auto-discovered global `AGENTS.md`.
The discovered global `AGENTS.md` (`~/.config/opencode/AGENTS.md`) stays the
user's alone.

The mechanism: the entrypoint appends the org file's path to `.instructions`
with `jq`, *after* the config merge. Doing it post-merge is load-bearing —
opencode's array-merge rule is **replace, not concatenate**, so if org
instructions were folded in as a config `instructions` entry, a user (or even
the org's own) `opencode.jsonc` setting `instructions` would silently discard
them. Appending after the merge sidesteps array-replace entirely.

Final instruction precedence, all additive:

```
Konrad environment.md  →  org AGENTS.md  →  user AGENTS.md  →  project AGENTS.md
```

(The first two are `instructions` entries; the last two are opencode's own
global + project `AGENTS.md` discovery.)

## Semantics: defaults, not enforcement

The org folder is just files in the user's own home directory. A determined user
can read and edit them. konrad does **not** try to lock that down — that would
need read-only system locations or signing, a separate feature with a much
larger surface.

So "add-only" describes the merge *precedence* (the user layer stacks on top of
org), **not** a permission lock. The docs say this explicitly so an org doesn't
mistake the layer for policy enforcement. If you need config a user genuinely
can't override, this isn't the mechanism — that's a future, separate concern.

## How it composes (the mechanism in one place)

- **Host (`bin/konrad`):** resolves `ORG_CFG_DIR` / `USER_CFG_DIR` under
  `~/.config/konrad/`, runs `migrate_flat_config()`, then bind-mounts each layer
  dir **whole** and read-only into the container at
  `/home/node/.config/konrad/{org,user}` (each gated on existence). Whole-dir
  mounts (rather than the old per-item mounts) keep the two layers symmetric and
  let the entrypoint own which files within a layer matter.
- **Image (`entrypoint.sh`):**
  - `opencode.jsonc` — left-folds `[baked, org?, user?]` through
    [merge-config.js](../../image/merge-config.js) (generalized to an N-input
    fold for this), always running the merge so the output is the same
    comment-stripped JSON on every path.
  - org instructions — `jq '.instructions += ["…/org/AGENTS.md"]'` after the
    merge (see decision 4).
  - `agents/` + `skills/` — `cp` org's tree over baked, then user's over org
    (later layer wins on name collision).
  - `fonts/` — symlink `org/fonts` (`konrad-org`) and `user/fonts`
    (`konrad-user`) into the fontconfig search path, one `fc-cache` at the end.

## Related

- Pairs with the API-key-handling roadmap item — org-wide secret provisioning is
  the same shape of problem (an org-shipped default a user inherits).
- A ready-to-adapt starter package lives in
  [docs/examples/org-package/](../examples/org-package/).
