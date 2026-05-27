# Pinning strategy and build reproducibility

How Konrad decides what each build is made of, why rebuilds stay cheap for
users, and how to diagnose a regression after the fact. For the *tag scheme*
on the registry and when `VERSION` bumps, see
[versioning-and-releases.md](versioning-and-releases.md) — this note covers
inputs and layers, that one covers versions and tags.

## The principle

Every meaningful input is digest- or version-locked in
[image/locks/](../../image/locks/). The [`.gitlab-ci.yml`](../../.gitlab-ci.yml)
`resolve-locks` job runs on GitLab daily, re-resolves each upstream, diffs
against the committed lock, and opens (auto-merges) an MR when anything moved.
The merge mirrors to GitHub and triggers a real rebuild via the `image/**` path
filter — so builds fire only when there is something genuinely new to build.
There is no scheduled cron rebuild on GitHub.

This is the build-side expression of the project's
[low-maintenance ethos](design-decisions.md#engineering-ethos--lightweight-composed-low-maintenance):
the freshness machinery is a bot plus upstream registries, not hand-tended
version bumps.

## Locked inputs

Each lock keys exactly one Dockerfile concern. Docker's layer cache reuses the
layer when the lock is byte-identical to last time; it rebuilds (and everything
downstream) when the lock moves. Local `konrad-dev --rebuild` reads the same
lock files as CI, so a developer's local build and the published image resolve
to identical digests.

| Component | Lock | Source | Notes |
| --- | --- | --- | --- |
| Base image (`node:26-trixie-slim`) | `base.lock` | Docker Registry HTTP API v2 | Full ref: `name:tag@sha256:…`. Major-bump the `:tag` part by hand (e.g., `node:26 → node:27`); the bot resolves the new digest on its next run. |
| `uv` source image (`ghcr.io/astral-sh/uv:latest`) | `uv.lock` | Same | Same shape as `base.lock`. |
| Python deps (`docling-slim[standard]`, `pypdf`, `pdfplumber`, `pdf2image`, `reportlab`, `openpyxl`, `pandas`, `onnxruntime`) | `python.lock` from `python.spec` | `uv pip compile --torch-backend=cpu --python-version=3.13` | |
| `opencode-ai`, `npm` | `npm.lock` | `npm view <pkg> version` | |
| `typst` | `typst.lock` | GitHub releases API for `typst/typst` | |

The win: a typical "only opencode-ai bumped" day rebuilds only the npm layer
and downstream — a small user pull on the next `konrad --update`. No-op days
fire no build at all — the user pull is a manifest poll only.

## Floating (one input)

| Component | Source | Why no lock |
| --- | --- | --- |
| apt packages | Whatever Debian trixie currently ships | apt's RUN layer cache invalidates only when its parent `FROM` changes — i.e., when `base.lock` bumps. So apt naturally refreshes whenever Debian/Node ship a new base image, picking up the current package index at that point. No separate apt lock needed. |

Docling models live in their own lock (`models.lock`) — see
[ROADMAP.md](../../ROADMAP.md) for that follow-up; today they re-download
whenever the Python venv layer rebuilds.

The Dockerfile [carries this list as a comment block](../../image/Dockerfile)
at the top so the surface is visible at a glance. Keep that block and this
table in sync when changing how a component is pinned.

## Reproducible layers

CI builds with `SOURCE_DATE_EPOCH=0` and `rewrite-timestamp=true`, so BuildKit
normalises every file mtime before tar'ing a layer. Two builds whose layer
content is byte-identical therefore produce byte-identical layer digests, even
across different commits — which is what lets the lock-driven cache actually
spare users a re-download when content didn't change. (Local `konrad-dev
--rebuild` keeps current-time mtimes for debugging convenience; its image lives
under `konrad:local`, separate from the published `:latest`, so there's no
cache interaction.)

## Diagnosing regressions

Every published image carries `/etc/konrad/build-manifest.json` — a snapshot of
dpkg / npm / pip versions plus build metadata. Dump it:

```sh
podman run --rm --entrypoint cat \
  ghcr.io/jlbauss/konrad:latest /etc/konrad/build-manifest.json | jq .
```

To diff two builds when something worked yesterday and broke today:

```sh
podman run --rm --entrypoint cat \
  ghcr.io/jlbauss/konrad:0.1.2026-05-22 \
  /etc/konrad/build-manifest.json > yesterday.json

podman run --rm --entrypoint cat \
  ghcr.io/jlbauss/konrad:0.1.2026-05-23 \
  /etc/konrad/build-manifest.json > today.json

diff <(jq -S . yesterday.json) <(jq -S . today.json)
```

The diff names every package whose version changed between the two builds,
which is enough to bisect any regression to its upstream cause. The dated,
immutable `:0.X.<date>` tags are always rollback-eligible — see
[versioning-and-releases.md](versioning-and-releases.md) for the tag scheme.
