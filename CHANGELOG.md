<!--
SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Changelog

All notable, user-facing changes to konrad. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); konrad follows
[semantic versioning](CONTRIBUTING.md#versioning) (pre-1.0: `0.X.Y`).

Entries stay terse — the *why* lives in the git commit log and the
[ARCHITECTURE.md](ARCHITECTURE.md), linked rather than restated. Each release
publishes as `:0.X.Y`, `:0.X`, `:latest`, and an immutable
`:0.X.Y-YYYY-MM-DD` daily rebuild (see the
[versioning](CONTRIBUTING.md#versioning)).

## [Unreleased]

### Changed
- Fewer permission prompts: the agent now acts freely inside its sandbox and
  asks only before an irreversible `rm -rf` of your real `/workspace` files.
  Root (`sudo`), host container/cluster control (`podman`/`docker`/`kubectl`),
  and the secrets volume are denied outright; network stays open because the
  egress firewall — not a per-command prompt — is the real boundary. Permissions
  now live once in the baked defaults; agents carry only their deltas.

## [0.9.2] - 2026-06-13

### Fixed
- Egress firewall no longer blocks built-in providers (OpenRouter, Anthropic,
  OpenAI, …) enabled with just an API key or `/connect`. These carry no URL in
  your config, so the proxy now resolves them to a host via a baked,
  models.dev-derived map plus the providers you've connected (`auth.json`) —
  previously only providers with an explicit `baseURL` were allowed.

### Changed
- The firewall allow-list **live-reloads** when you connect a provider
  mid-session — connecting now takes effect within seconds, with no konrad
  restart and no `--no-firewall` (API-key providers; an OAuth first-connect
  still needs a one-time `--allow-host`).

## [0.9.1] - 2026-06-13

### Fixed
- The opencode layer is now reproducible across rebuilds — npm/Node build cruft
  (debug logs, V8 compile cache) no longer leaks into image layers, so an
  unrelated `python.lock` bump stops needlessly re-shipping the opencode layer.
  Sibling to the 0.9.0 venv-layer dedupe.

### Changed
- opencode ships a single CPU-portable binary (`-baseline` on x64) instead of one
  picked from the build host's CPU — halves the opencode layer (~104 → ~52 MB)
  and removes a latent illegal-instruction risk on older x64 CPUs.

## [0.9.0] - 2026-06-11

### Changed
- The Python venv now ships as three `COPY` layers — torch (~700 MB), the large
  numeric wheels (opencv/scipy/numpy/onnxruntime/sympy, ~450 MB), and the rest
  (~360 MB) — instead of one ~1.5 GB layer. A `python.lock` bump that only moves
  a small dep (the near-daily case) now re-pulls just the light layer; torch and
  the numeric set dedupe. Sibling to the 0.6.0 model-layer dedupe. Rationale:
  [ARCHITECTURE.md](ARCHITECTURE.md#build--reproducibility).

## [0.8.0] - 2026-06-10

### Added
- Egress firewall, **on by default**. The agent container now runs on an
  isolated Podman network with no direct internet route and reaches the outside
  only through a sidecar filtering proxy (tinyproxy, run from the same image)
  that allows just an allow-list: the model providers derived from your merged
  config, plus `registry.npmjs.org` (the on-demand provider SDK adapters).
  Shrinks the blast radius of a prompt-injected agent exfiltrating data.
  `models.dev`, PyPI, and the open web are blocked by default. Extend it per-run
  with
  `--allow-host <host>` or permanently via an `allowed_hosts` file in your
  org/user layer; `--no-firewall` (or `KONRAD_FIREWALL=0`) opts out. Design:
  [ARCHITECTURE.md](ARCHITECTURE.md#state-secrets--isolation).

## [0.7.0] - 2026-06-10

### Added
- Dev-container self-testing now works on macOS hosts too: a `dockerPath` shim
  ([.devcontainer/podman-vscode.sh](.devcontainer/podman-vscode.sh)) creates the
  dev container via the podman machine's bundled *rootful* connection (the
  machine's default connection stays rootless) and swaps the rootless-only
  keep-id mapping for explicit uid/gid maps; `bin/konrad` does the same for the
  nested runtime container when it detects that daemon. Contributor-facing;
  one-time setup in [CONTRIBUTING.md](CONTRIBUTING.md).
- Self-testing now mounts your real `~/.config/konrad` layer into the runtime
  container (the dev container binds it in; `bin/konrad` re-mounts it from the
  daemon-visible host path), so a self-test composes `baked < org < user` and
  uses your own model / agents / skills exactly like a normal run — instead of
  running bare baked config. Removes the previous "config layers skipped while
  self-testing" divergence.
- `scripts/selftest.sh` — the realistic end-to-end contributor/agent loop: runs
  the image smoke test, then drives a real `konrad run` through `bin/konrad` and
  asserts the agent answers. The model defaults to the one in your konrad config
  (overridable with `--model` / `KONRAD_SELFTEST_MODEL`, any provider); the model
  stage degrades to a SKIP when no model/credential is usable, so a red result
  always means the runtime broke.

### Fixed
- `scripts/smoke-test.sh` now skips its org-layer-compose check on a remote
  daemon (dev-container self-testing) instead of failing on an unreachable
  bind-mount source — matching what `bin/konrad` already does and what
  [CONTRIBUTING.md](CONTRIBUTING.md) already documented. CI (local daemon) is
  unaffected.

## [0.6.0] - 2026-06-09

### Changed
- Docling model layers are now commit-pinned (`image/locks/models.lock`),
  metadata-stripped, and split one-per-model — so an unrelated lock bump no
  longer changes their bytes, and an image update re-pulls a model only when
  that model actually changed, not the whole ~1.1 GB set. The models also move
  out of `$HOME` to a root-owned `/opt/models`, so the runtime user now owns its
  entire home (no more permission-denied on first write to a new `$HOME` dir).
  Rationale: [ARCHITECTURE.md](ARCHITECTURE.md#build--reproducibility).

## [0.5.1] - 2026-06-08

### Changed
- Licensing now follows the [REUSE](https://reuse.software) specification — every
  file's copyright + license is declared in `REUSE.toml` / `LICENSES/` (SPDX-clear,
  `reuse lint`-verified, CI-gated); `NOTICE` retired, its acknowledgements moved
  into the README.
- Documentation consolidated to single canonical homes — `ARCHITECTURE.md` (design
  and the *why*), this `CHANGELOG.md` (replacing ROADMAP's `## Implemented`), and
  the versioning / dev-release / commit conventions in their canonical docs.

## [0.5.0] - 2026-06-08

### Added
- `konrad run "<prompt>"` — non-interactive one-shot mode: execs `opencode run`
  instead of the TUI, streams the answer to stdout, propagates the exit code.
  Everything after `run` passes through to opencode verbatim.
- `--profile <name>` — isolates a run's opencode state + cache in throwaway
  `konrad-state-<name>` / `konrad-cache-<name>` volumes (credentials stay
  shared); `--reset --profile` wipes just that profile.

### Changed
- `-v` no longer dumps raw HTTP traffic; opt in with `KONRAD_TRACE_FETCH=1`.

## [0.4.1] - 2026-06-03

### Added
- Dev-container self-testing — drive the host Podman daemon from inside the dev
  container to exercise the runtime image (Linux hosts). Contributor-facing.

## [0.4.0] - 2026-06-02

### Added
- Org configuration layer — a third config tier merged `baked < org < user`,
  letting an organization ship fleet-wide defaults (extra models, an internal
  provider endpoint, house skills/agents, a corporate `AGENTS.md`, fonts)
  without forking the image or editing each user's config.

## [0.3.1] - 2026-06-02

### Fixed
- Keep `/etc/konrad` traversable for the runtime user (`COPY --chmod` was
  setting the parent-dir mode too strictly).

## [0.3.0] - 2026-06-01

### Added
- `frontend-design` bundled skill, plus ready-made `grill-me`, `write-a-skill`,
  and `image-editing`.

## [0.2.1] – [0.2.6] - 2026-05-29

A same-day run of CLI and release-plumbing polish.

### Added
- `konrad --check-updates`; a pull-progress layer counter; `--version` printed
  at the tail of `--update` / install.

### Changed
- Three-segment pre-1.0 versions (`0.X.Y`) with hyphen-separated dated image
  tags; image rebuilds decoupled from CLI-only `VERSION` bumps; lock-file noise
  reduced (dropped the npm pin, stripped `python.lock` comments).

### Fixed
- `konrad --update` unbound-variable crash (`REGISTRY_IMAGE` /
  `INSTALL_REMOTE_URL` expansions).

## [0.2] - 2026-05-27

First public alpha — the GitLab repo and the GHCR package went public (the
GitHub mirror stays a private CI surface). The accumulated private-development
feature set at first public release:

### Added
- Sandboxed opencode in a rootless Podman container (`--userns=keep-id`).
- Host-mergeable configuration layering and a per-user `~/.config/konrad/`.
- Bundled skills: `pdf`, `spreadsheets`, and `quality-assurance` (the
  cross-skill visual + language verification cycle every producer skill runs).
- A curated SIL OFL font palette plus a user font-overlay path.
- Multi-arch image (amd64 + arm64) with per-arch native smoke tests.
- Frictionless `curl … | sh` install (CLI on PATH, no clone needed).
- Distinct CLI-vs-image version reporting in `konrad --version`.

### Changed
- Relicensed GPL-3.0 → AGPL-3.0.

> Pre-`0.2` development is summarized here rather than itemized — it predates
> the public project. The deeper origin story is in the "Day-zero history" of
> the [versioning](CONTRIBUTING.md#versioning) and the git log.

## [0.1] - 2026-05-23

Pre-public stabilization line (private): float-everything pinning by digest,
smoke-gated daily CI on GitHub Actions, and the GHCR publish path went live.
