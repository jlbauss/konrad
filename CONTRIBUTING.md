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
| VS Code Dev Containers entry point (experimental, second consumption path — see ROADMAP) | `devcontainer/` |
| Roadmap and idea backlog | `ROADMAP.md` |
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

## When to update ROADMAP.md

- A real idea worth keeping but not doing now → add it.
- A decision we made and are sticking with → don't add it (commit message is enough).
- A known shortcoming we've accepted as a trade-off → add it, so it doesn't get forgotten.

## When to update README.md

- Anything that changes how a user installs, runs, or thinks about konrad.
- A new subcommand or flag.
- A new external dependency (e.g. a tool the user has to install on the host).

## When to update AGENTS.md (`AGENTS.md` at the repo root)

This is the repo-level AGENTS.md, loaded by an agent working _on_ konrad (e.g. Claude editing this codebase). Update when:

- A new tool, file, or directory the agent should know about.
- A new convention or constraint the agent should follow.
- A structural change (config layering, state tiers, image stages).

Konrad's _own_ model instructions live separately at `image/konrad-defaults/instructions.md` (baked into the image, loaded by opencode at runtime). Edit that one when you're tuning how konrad behaves toward its end users.

Keep both tight — every byte competes with task context inside the model's window.

## Out of scope right now

- Windows host support. Podman with `--userns=keep-id` is Linux/macOS only.
- Tests. See `ROADMAP.md` for the CI item — that's where tests would land.
