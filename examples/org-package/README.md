# Example org layer (git-native)

A starter for the konrad **org config layer** — the layer that lets an
organization ship defaults every user inherits (merged `baked < org < user`).
Publish an adapted copy of this directory as a git repository on your forge;
each member then subscribes once:

```sh
konrad org add https://git.example.com/acme/konrad-org
```

That clones the repo to `~/.config/konrad/org/<name>/`, and every
`konrad update` (or `konrad org sync`) re-syncs it — the layer is a **managed
mirror** that tracks your branch, so shipping an update to the fleet is just
`git push`. Private repos need no konrad-side auth: the member's existing git
credentials (a forge CLI login such as `gh`/`glab auth login`, or SSH) apply.

See [README → Configuration → "For organizations"](../../README.md#for-organizations)
for the user-facing overview and [ARCHITECTURE.md → Configuration & instructions](../../ARCHITECTURE.md#configuration--instructions)
for the *why*.

## What's here

```text
org-package/                 Publish this as a git repo — the repo IS the layer.
├── opencode.jsonc           Org-wide config: an internal provider + a declared model.
├── instructions/            Org instructions — every *.md here loads on the system channel.
│   └── house-rules.md
├── skills/
│   └── house-style/
│       └── SKILL.md         A trivial example house skill.
└── hooks/
    └── post-sync            Optional. Runs host-side after add + every sync (see below).
```

The layer holds the same optional pieces as a user's `~/.config/konrad/user/`
(`opencode.jsonc`, `agents/`, `skills/`, `instructions/`, `AGENTS.md`,
`fonts/`, `allowed_hosts`); this example populates three plus a hook. Ship only
what your org needs. Several orgs can coexist as sibling layers — they fold in
alphabetical name order (pick precedence with a numeric prefix: `10-core`,
`20-team`), each still below every user's own layer.

## The post-sync hook (trust boundary)

`hooks/post-sync`, when present and executable, runs **on the member's machine**
after the initial `konrad org add` and after every successful sync — the one
place org code runs outside konrad's sandbox. Subscribing to a layer *is* the
decision to trust its code; konrad adds no prompt. Use it for the few jobs plain
config can't express — mirroring a wiki into `~/.config/konrad/context/` for the
agent to grep, or deriving per-member identity from your forge's CLI — and keep
it idempotent: it runs on every sync, changed or not. The example hook just
stamps a marker file so you can watch the mechanism; replace or delete it.

## Adapt it

- **`opencode.jsonc`** — point `baseURL` at your real internal gateway, declare
  the models you've actually deployed, add any provider keys via opencode's
  `{env:VAR}` placeholders. This merges *under* each user's
  `user/opencode.jsonc`, so a user can still override or add on top.
- **`instructions/*.md`** — your house rules. Every `.md` here loads additively
  on the system instructions channel (precedence: Konrad's `environment.md` →
  **org** → user `AGENTS.md` → project `AGENTS.md`). Split rules across files,
  or have the hook generate one. (A single `AGENTS.md` at the layer root still
  works as a back-compat alias.)
- **`skills/`**, **`agents/`**, **`fonts/`**, **`allowed_hosts`** — house
  skills, house agents, corporate fonts, extra egress-firewall hosts. Same
  layering: org sits between baked and user.

## Note: defaults, not enforcement

Everything here lands in the user's own home directory, so a determined user can
edit it (local edits to tracked files are simply clobbered on the next sync).
The org layer is a **defaults** mechanism, not a policy lock — "add-only"
describes the merge precedence (user stacks on top), not a permission boundary.
If you need config a user can't override, this isn't it.
