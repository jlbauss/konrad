# Example org package

A starter for the konrad **org config layer** — the layer that lets an
organization ship defaults every user inherits (merged `baked < org < user`).
Copy this directory, adapt the contents to your org, and distribute it however
you distribute internal tooling (a `git clone`, an MDM-pushed folder, a
`curl … | sh`, a `.pkg`/`.deb`, …). The only contract is the final resting
place: **`~/.config/konrad/org/`** in each user's home.

See [README → Configuration → "For organizations"](../../../README.md#for-organizations)
for the user-facing overview and [ARCHITECTURE.md → Configuration & instructions](../../../ARCHITECTURE.md#configuration--instructions)
for the *why*.

## What's here

```
org-package/
├── install.sh        Drops org/ into ~/.config/konrad/org/. Adapt or replace.
└── org/              The payload — exactly the tree that lands at ~/.config/konrad/org/.
    ├── opencode.jsonc   Org-wide config: an internal provider + a declared model.
    ├── instructions/    Org instructions — every *.md here loads on the system channel.
    │   └── house-rules.md
    └── skills/
        └── house-style/
            └── SKILL.md  A trivial example house skill.
```

`org/` holds the same optional pieces as a user's `~/.config/konrad/user/`
layer (`opencode.jsonc`, `agents/`, `skills/`, `instructions/`, `AGENTS.md`,
`fonts/`); this example populates three of them. Drop in only what your org needs.

## Try it

```sh
./install.sh
konrad        # the org provider/model, instructions, and skill are now in play
```

`install.sh` copies `org/` to `~/.config/konrad/org/` and is idempotent (re-run
to update). It never touches `~/.config/konrad/user/` — a user's own layer is
theirs.

## Adapt it

- **`org/opencode.jsonc`** — point `baseURL` at your real internal gateway,
  declare the models you've actually deployed, add any provider keys via
  opencode's `{env:VAR}` placeholders. This merges *under* each user's
  `user/opencode.jsonc`, so a user can still override or add on top.
- **`org/instructions/*.md`** — your house rules. Every `.md` here loads
  additively on the system instructions channel (precedence: Konrad's
  `environment.md` → **org** → user `AGENTS.md` → project `AGENTS.md`). Split
  rules across files, or have a tool generate one. (`org/AGENTS.md` still works
  as a single-file back-compat alias.)
- **`org/skills/`**, **`org/agents/`**, **`org/fonts/`** — house skills, house
  agents, corporate fonts. Same layering: org sits between baked and user.

## Note: defaults, not enforcement

Everything here lands in the user's own home directory, so a determined user can
edit it. The org layer is a **defaults** mechanism, not a policy lock — "add-only"
describes the merge precedence (user stacks on top), not a permission boundary.
If you need config a user can't override, this isn't it.
