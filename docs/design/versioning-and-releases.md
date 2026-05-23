# Versioning and releases

## Why this doc exists

Konrad ships as a container image. Users don't compile from source; they `konrad update` and get whatever's at `ghcr.io/jlbauss/konrad:latest`. That makes the version semantics user-facing: when a user reports a bug, "I'm on `0.3.2026-04-15`" needs to mean something unambiguous, and the upgrade path needs to be obvious.

This doc captures the rules so they stay consistent across the project's lifetime.

## Version states

Konrad's lifecycle has two version regimes.

### Pre-1.0 (where we are today)

`VERSION` at the repo root holds a value like `0.X`. No PATCH is written.

- **MAJOR is always 0.** We don't promise non-breaking upgrades yet.
- **X bumps for any functional change** to `image/`, `bin/konrad`, baked skills/agents, or `image/konrad-defaults/`. Doc-only, CI-only, and ROADMAP-only changes don't bump.
- **The date suffix on image tags acts as the patch identifier.** `0.1.2026-05-23` is "konrad code at 0.1 + packages as of 2026-05-23." Two builds with the same `VERSION` but different dates differ only in floating-pin re-resolution.

Why no third number pre-1.0? The bump cadence is so coarse (every functional change is more-or-less a minor) that a third digit would be noise. The date is more honest about what makes two builds differ — it's "what was the upstream world like on the day of this build."

### Post-1.0

`VERSION` holds full semver: `X.Y.Z`.

- **MAJOR** — breaking change to user-facing surface area:
  - `opencode.jsonc` schema in a way that requires migration
  - CLI subcommand rename or removal
  - Removed bundled skill or agent
  - Renamed path inside `/etc/konrad/` or `~/.config/opencode/` that users depend on
  - Debian or Node major bump (because base-image major bumps frequently break user overrides)
- **MINOR** — additive:
  - New bundled skill, agent, or font
  - New CLI subcommand or flag
  - New layered-config slot in `~/.config/konrad/`
  - New environment variable
- **PATCH** — fix / refresh:
  - Bug fix to existing behavior
  - Pure floating-pin refresh (security or bug fixes from upstream)
  - Doc updates often skip a bump entirely

When does 1.0 happen? When konrad is stable enough to make "no breaking change without a major bump" a credible promise. Probably gated on the Tier-1 ROADMAP work (egress firewall, local models flawless, security audit, documentation pass). It's a deliberate event, not a date.

## Tag scheme on the registry

All published at `ghcr.io/jlbauss/konrad`. Two tag families, plus PR tags.

### Pre-1.0

| Tag | Mutable? | Meaning |
| --- | --- | --- |
| `:0.X.YYYY-MM-DD` | immutable | konrad code at `0.X` + packages as of that day. The rollback handle. |
| `:0.X` | rolling | newest passing daily build on the `0.X` line |
| `:latest` | rolling | newest passing build, currently of the newest minor line |
| `:<short-sha>` | immutable | per-commit; for bisecting |

When `VERSION` bumps `0.X → 0.X+1`: `:0.X` stops getting new builds (frozen at last good). Users on `:0.X` see no fresh updates until they upgrade. The immutable `:0.X.<date>` tags remain pullable indefinitely.

### Post-1.0

| Tag | Mutable? | Meaning |
| --- | --- | --- |
| `:X.Y.Z-YYYY-MM-DD` | immutable | full semver + dated rebuild (floating pins re-resolved on that day) |
| `:X.Y.Z` | rolling | newest passing daily build for that specific patch version |
| `:X.Y` | rolling | newest passing patch on the `X.Y` line |
| `:X` | rolling | newest passing minor on the `X` major line |
| `:latest` | rolling | newest passing across the whole project |
| `:<short-sha>` | immutable | per-commit; for bisecting |

CI continues to daily-rebuild and re-publish under the current `X.Y.Z`. The date suffix lets users pin to "the `X.Y.Z` that was current on a specific day" if upstream-regression debugging is needed without forcing a version bump on every floating-pin refresh.

### Pull request tags

| Tag | Lifetime | Purpose |
| --- | --- | --- |
| `:pr-<num>` | replaced on every PR push; should be deleted on merge or close | Reviewer pulls this to interactively test a proposed change before merging |

PR builds run through the same build → smoke gate as main, but publish *only* to `:pr-<num>`. They never touch `:latest` or any release tag. Failing smoke blocks the PR-tag publish — same safety pattern as main.

Interactive testing recipe for reviewers:

```sh
podman pull ghcr.io/jlbauss/konrad:pr-42
KONRAD_IMAGE=ghcr.io/jlbauss/konrad:pr-42 konrad shell      # poke around
KONRAD_IMAGE=ghcr.io/jlbauss/konrad:pr-42 konrad            # run for real
```

**Fork PRs.** Contributors pushing from a fork can't write to `ghcr.io` (GitHub's default token scope on fork PRs is read-only). For external contributions, the maintainer pushes the contributor's branch to the upstream repo as a branch (e.g. `pr/123`) so CI can publish a `:pr-<num>` tag. Trade-off accepted: external contributors don't get auto-published PR images out of the gate, but their code still runs through CI smoke; the maintainer pulls the branch up when they want to test interactively.

## When to bump VERSION

**In the same PR as the change.** Reviewer verifies the bump matches the change's semver impact.

Examples:

| Change | Pre-1.0 bump | Post-1.0 bump |
| --- | --- | --- |
| Add a new bundled skill | `0.1 → 0.2` | `1.2.3 → 1.3.0` (minor) |
| Fix a bug in an existing skill | `0.1 → 0.2` | `1.2.3 → 1.2.4` (patch) |
| Floating-pin refresh that pulled a security fix (daily CI) | no bump (date carries it) | no bump (date carries it) |
| Rename `konrad shell` to `konrad bash` | `0.1 → 0.2` | `1.2.3 → 2.0.0` (major — breaking) |
| Add a new CLI flag | `0.1 → 0.2` | `1.2.3 → 1.3.0` (minor) |
| Update README typo | no bump | no bump |
| Update CI workflow | no bump | no bump |
| Bump Debian base from trixie to forky | `0.1 → 0.2` | `1.2.3 → 2.0.0` (major) |

If a single PR bundles multiple concerns (rare; we prefer separate commits per concern — see CONTRIBUTING.md), the highest-impact change determines the bump.

## Git tags

- **Pre-1.0**: optional. Tag `v0.X` at moments that feel like a release. The image tag `:0.X` already serves as the immutable handle for users; the git tag is for humans navigating the history.
- **Post-1.0**: every MAJOR or MINOR release gets a git tag `vX.Y.0`. PATCH releases skip the git tag (CI tags the image, which is enough). MAJOR releases also get a GitHub Release with a written changelog.

## GitHub Releases

- **Pre-1.0**: skip. The ROADMAP `## Implemented` section serves as the dated changelog.
- **Post-1.0**: for each MAJOR/MINOR — title `konrad vX.Y.0`, body with "what's new / what's broken / migration notes for breaking changes," linked to the git tag.

## Day-zero history

The pre-1.0 chapter started on **2026-05-23** with `VERSION=0.1`, when the registry-publish path went live (see ROADMAP entry of that date). Earlier development happened on `main` without a `VERSION` file and isn't representable in this scheme; the dated `Implemented` entries in ROADMAP are the authoritative history for that period.

**`0.1` is the pre-public stabilization line** — the version that existed while the repo was still private and CI / publishing / smoke gates were getting their final shakedown. Functional changes during this phase didn't always bump (the bump-in-same-PR rule itself landed mid-stream); the dated image tags `:0.1.YYYY-MM-DD` are the authoritative per-day history.

**`0.2` will be the first public alpha** — bumped as part of the "Set public" ROADMAP work. The bump signals the regime change: from this point forward, every functional change bumps `VERSION` in its PR, and the version line a user is on actually means something to them. Treat it as the day-one anchor for outside contributors and consumers.
