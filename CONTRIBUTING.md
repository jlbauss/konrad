# Contributing to konrad

Notes for future-me. Short and operational.

## Local development loop

```sh
# Edit files...
./scripts/build-image.sh           # rebuild image after Dockerfile / opencode/ changes
konrad rebuild                     # equivalent, if the CLI is installed
shellcheck bin/konrad image/entrypoint.sh scripts/*.sh    # lint
```

There's no test suite yet. The closest things to validation are:

- `bash -n <script>` — parse check.
- `shellcheck <script>` — static analysis. Should stay clean.
- `./scripts/build-image.sh` — the "the image actually builds" smoke test.
- A live run: `cd /tmp/konrad-test && konrad version` then `konrad shell` to poke around.

## What goes where

| Concern | Lives in |
| --- | --- |
| The container artifact | `image/` (Dockerfile + bundled `opencode/` config) |
| The host-side CLI | `bin/konrad` |
| Install / build helpers | `scripts/` |
| VS Code Dev Containers entry point | `.devcontainer/` |
| Backlog of deferred work | `BACKLOG.md` |
| Upstream attribution | `NOTICE` |

If a change touches multiple concerns, prefer separate commits per concern.

## Commit style

Conventional commit subject, no scope prefix unless useful:

```
short imperative subject in lowercase

body explaining *why*, wrapping at ~72 cols. include surprising
constraints or non-obvious tradeoffs. don't re-state what the diff
shows.

Co-Authored-By: ...   (only when applicable)
```

Use multi-line bodies for any change that needed a design decision. The git log is the project's primary design history — keep it useful.

## When to update BACKLOG.md

- A real idea worth keeping but not doing now → add it.
- A decision we made and are sticking with → don't add it (commit message is enough).
- A known shortcoming we've accepted as a trade-off → add it, so it doesn't get forgotten.

## When to update README.md

- Anything that changes how a user installs, runs, or thinks about konrad.
- A new subcommand or flag.
- A new external dependency (e.g. a tool the user has to install on the host).

## When to update AGENTS.md (`image/opencode/AGENTS.md`)

- A new tool the agent should know about.
- A new convention the agent should follow.
- A change to the file-based planning workflow or the `.agent/` layout.

Keep AGENTS.md tight — every byte competes with task context inside the model's window.

## Out of scope right now

- The bundled skills under `image/opencode/skills/`. They come from MiniMax; we don't maintain them. See BACKLOG.md "Skills hygiene" for the items we'll eventually tackle.
- Windows host support. Podman with `--userns=keep-id` is Linux/macOS only.
- Tests. See `BACKLOG.md` for the CI item — that's where tests would land.
