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
