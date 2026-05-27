# Design decisions

A short, opinionated record of Konrad's load-bearing choices, so future
maintainers can tell what's a hard constraint and what's a preference.
Decisions with their own deep-dive note are summarised here in one line and
linked — this page is the index of *why Konrad is the way it is*; the linked
notes carry the full rationale.

## Engineering ethos — lightweight, composed, low-maintenance

The guiding principle behind every other decision on this page: **Konrad
should stay lightweight and lean on pre-existing building blocks rather than
custom code.** Prefer gluing well-maintained upstreams together in a sensible
way over writing and owning bespoke machinery. The goal is to drive the
ongoing maintenance burden toward zero — ideally Konrad keeps working and
stays current even through periods when no one is actively developing it.
Follow established best practices rather than inventing local ones. When a
feature can be had by configuring an existing tool instead of shipping code,
take the configuration. This is why, for example, model discovery's custom
plugin was dropped, the deep-merge is a tiny self-contained step rather than a
framework, and the whole pinning/rebuild story is delegated to a bot plus
upstream registries (see below).

## The artifact and the runtime

- **Podman, not Docker.** Open-source, free for commercial use, ergonomic on
  macOS. `--userns=keep-id` lets the container's `node` user share a UID with
  the host user, so bind-mounted files have sane ownership. Docker support is
  in [ROADMAP.md](../../ROADMAP.md).
- **The image is the canonical artifact.** `image/Dockerfile` builds
  `konrad:latest`. `bin/konrad` is the primary consumer; the experimental
  `devcontainer/devcontainer.json` is a second consumer (see
  [ROADMAP.md](../../ROADMAP.md)).
- **Optimised for Qwen3.6-class local models.** The agent body in
  [image/opencode/agents/konrad.md](../../image/opencode/agents/konrad.md) is
  sized and worded for a ~30B-class MoE local model — terse-but-deliberate, no
  Claude-style verification loops. Bigger frontier models work fine; smaller
  (<10B) ones may need prompt softening. The specific recommendation we test
  against is `qwen/qwen3.6-27b`.

## Config and instructions

- **Layered config, not replacement.** Konrad's baked `opencode.jsonc` is
  composed with the user's `~/.config/konrad/opencode.jsonc` at every container
  start via a self-contained Node deep-merger. Users add a provider without
  losing the defaults; Konrad ships a new local engine and the user gets it
  automatically on next update. The merge step is in `image/entrypoint.sh` and
  runs *before* opencode loads anything.
- **`AGENTS.md` is the user's slot; `instructions` is Konrad's.** opencode
  loads both, additively, into the system prompt. By assigning each side its
  own loading mechanism, the two never collide — and a user override can't
  silently discard Konrad's baked instructions (arrays replace; objects merge).
- **Minimal hardcoded defaults.** Provider endpoints ship pre-wired but model
  lists ship empty — users declare whichever model they've loaded in
  `~/.config/konrad/opencode.jsonc`. Earlier versions auto-discovered models
  via the `opencode-models-discovery` plugin, but the startup cost wasn't worth
  it; an inline replacement is on the roadmap. **No top-level `"model"` is set
  in the baked default** — opencode prompts on first run, then remembers your
  choice in the `konrad-state` volume.

## State, secrets, and isolation

- **Three-tier state; `.agent/` belongs to the agent.** Workspace `.agent/`
  is the agent's end-to-end (task plan, artifacts, scratch, quality-assurance
  evidence); opencode logs land in a host XDG path; auth/cache/UI-state live in
  named volumes; sessions are ephemeral. Full rationale in
  [state-isolation.md](state-isolation.md).
- **No per-project secrets in the workspace.** Auth credentials live only in
  the `konrad-secrets` named volume. Users who don't read `.gitignore`
  carefully still can't accidentally publish their tokens.

## Build, release, and CI

- **Lock every input; a bot maintains the locks; smoke-gate the publish.**
  Every meaningful build input — base image, uv source image, Python deps, npm
  packages, Typst — is digest- or version-locked; a bot re-resolves them and
  opens auto-merging MRs only when something genuinely moved, so builds fire
  only when there's something new to build. Full rationale, the lock table, and
  the regression-diagnosis recipe in [pinning-and-build.md](pinning-and-build.md).
- **CI runs on a GitHub mirror; the primary repo stays on `gitlab.git.nrw`.**
  A one-way GitLab → GitHub push mirror replicates every commit; GitHub Actions
  runs build → smoke → publish to `ghcr.io/jlbauss/konrad`. The GitHub side is
  purely a CI execution surface — no issues, no MRs, no day-to-day work. Why:
  gitlab.git.nrw's shared runners don't permit the privileged-container
  operations Podman-in-Docker needs, and GitHub Actions gives hosted runners
  (free for amd64; the arm64 runners are billable premium minutes while the
  mirror stays private — it's kept private by choice for now, and the
  lock-driven CI cadence keeps that cost negligible. Flipping the mirror
  public would make arm64 free, but that's an option, not a plan). Trade-off
  accepted: CI status visibility lives on GitHub, not GitLab MRs, until a
  GitLab Commit Status API webhook is wired up.

## Licensing

- **AGPL v3.** Compatible with all bundled upstream licenses (MIT, Apache 2.0,
  OFL 1.1). Strong copyleft is a deliberate choice for a sandbox-style tool — if
  someone extends Konrad or runs it as a hosted service, the improvements come
  back to the commons. AGPL's network-use clause closes the SaaS loophole left
  open by plain GPL: a fork offered as a remote agent over an API still has to
  publish its source.
