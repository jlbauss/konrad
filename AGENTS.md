# AGENTS.md

## What this repo is

konrad is a CLI (`bin/konrad`) that runs [opencode](https://github.com/sst/opencode) inside a sandboxed Podman container. The container image is the canonical artifact; the CLI and `.devcontainer/` are consumers of it.

## Validation (no test suite)

There are no automated tests. Validate changes with:

```sh
shellcheck bin/konrad image/entrypoint.sh scripts/*.sh   # lint — should stay clean
bash -n <script>                                          # parse check
./scripts/build-image.sh                                   # smoke test: image actually builds
cd /tmp/konrad-test && konrad version && konrad shell      # live smoke test
```

## Development loop

1. Edit files
2. `./scripts/build-image.sh` (or `konrad rebuild` if CLI is installed)
3. Run `konrad` or `konrad shell` to verify

Any change to `image/` (Dockerfile, entrypoint, defaults, agents) requires a rebuild before it takes effect. Changes to `bin/konrad` take effect immediately (it's a bash script).

## Architecture

| Directory | Purpose | Rebuild needed? |
|---|---|---|
| `image/` | Container build context — the canonical artifact | Yes |
| `image/konrad-defaults/` | Baked defaults → `/etc/konrad/` in image | Yes |
| `image/opencode/` | opencode-discoverable config → `~/.config/opencode/` in image | Yes |
| `bin/konrad` | Host-side CLI (bash) | No |
| `scripts/` | Install and build helpers | No |

Multi-concern changes: prefer separate commits per concern (CONTRIBUTING.md).

## Config layering

At container start, `image/entrypoint.sh` composes `~/.config/opencode/opencode.jsonc` from up to three layers via `image/merge-config.js`:

1. **Baked defaults** (`/etc/konrad/opencode-defaults.jsonc`)
2. **Runtime override** (generated from `KONRAD_PROVIDER_EXCLUDES` env var — adds unreachable providers to discovery plugin's exclude list)
3. **User override** (`~/.config/konrad/opencode.jsonc`, bind-mounted from host)

Merge semantics: **objects merge recursively (user wins on conflict), arrays replace entirely.** The array-replace rule is critical — setting `instructions` in a user override would discard konrad's base instructions. That's why users should use `AGENTS.md` for additions, not the `instructions` key.

User-shipped agents/skills/AGENTS.md from `~/.config/konrad/` are also layered in (overwrite on name collision — intentional escape hatch).

## Important constraints

- **Podman only** — `--userns=keep-id` is Podman-specific. Docker support is on the roadmap.
- **LM Studio excluded from auto-discovery** — upstream plugin bug emits invalid `modalities.output`. Pre-declared default model (`qwen/qwen3.6-35b-a3b`) works around it.
- **No top-level `model` key in baked defaults** — opencode prompts on first run and persists the choice in the `konrad-state` named volume.
- **`.agent/opencode/`** is operational state (sessions, sqlite, cache) — always gitignored. `.agent/task_plan.md`, `.agent/progress.md`, `.agent/findings.md` are working memory and committable at user discretion.
- **Python venv** at `/opt/venv` (on PATH). Extend with `uv pip install <pkg>`.
- **Debian renames**: `fd` → `fdfind`, `bat` → `batcat` (symlinked to canonical names in Dockerfile).
- **opencode Zen disabled** by default (`disabled_providers: ["opencode"]`).
- **No skills ship** in this version — directory removed, pending rebuild.

## Commit style

Conventional commits without scope prefix unless useful: `feat:`, `fix:`, `refactor:`, `docs:`, `chore:`. Multi-line body for any change involving a design decision — the git log is the project's design history.
