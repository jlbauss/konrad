# Versioning and releases

## Why this doc exists

Konrad ships as a container image. Users don't compile from source; they `konrad --update` and get whatever's at `ghcr.io/jlbauss/konrad:latest`. That makes the version semantics user-facing: when a user reports a bug, "I'm on `0.3.0-2026-06-04`" needs to mean something unambiguous, and the upgrade path needs to be obvious.

This doc captures the rules so they stay consistent across the project's lifetime.

## Version states

Konrad's lifecycle has two version regimes.

### Pre-1.0 (where we are today)

`VERSION` at the repo root holds a value like `0.X.Y`.

- **MAJOR is always 0.** We don't promise non-breaking upgrades yet.
- **Y (PATCH) bumps for a bug fix with no surface change** — same flags, same outputs, same behavior on the happy path. The fix to `konrad --update`'s `REGISTRY_IMAGE` unbound-variable error (2026-05-29) is a textbook patch.
- **X (MINOR) bumps for new functionality, behavior change, or anything a user might notice.** New bundled skill or agent, new CLI flag, renamed path, base-image major bump — all minor. There is no MAJOR slot pre-1.0, so changes that *would* be major post-1.0 land as minor here (the leading `0.` already telegraphs "may break"). Reset `Y` to 0 on a minor bump.
- **Doc-only, CI-only, and ROADMAP-only changes don't bump.**
- **The date suffix on image tags is the build-day identifier.** `0.2.1-2026-05-29` is "konrad code at 0.2.1 + packages as of 2026-05-29." Two builds with the same `VERSION` but different dates differ only in floating-pin re-resolution — that's not a code change, so it doesn't bump `Y`.

Why a third number pre-1.0? Without one, every functional change inflates `X`, and the minor lifetime starts measuring in hours rather than features — `X` stops signalling anything to users. Splitting fixes (patch) from features (minor) at the version level matches what npm/cargo already assume for `0.x.y` (compatible patches, potentially-breaking minors), and gives users a coarse "this is a quiet refresh" vs "this changed something" signal without forcing a 1.0 declaration before we're ready.

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
| `:0.X.Y-YYYY-MM-DD` | immutable | konrad code at `0.X.Y` + packages as of that day. The rollback handle. |
| `:0.X.Y` | rolling | newest passing daily build for that specific patch version |
| `:0.X` | rolling | newest passing patch on the `0.X` minor line |
| `:latest` | rolling | newest passing build, currently of the newest minor line |
| `:<short-sha>` | immutable | per-commit; for bisecting |

When `VERSION` bumps `0.X.Y → 0.X.Y+1` (patch): `:0.X.Y` freezes at the last passing build of that patch; `:0.X` rolls forward to the new patch. Users on `:0.X` get the fix automatically.
When `VERSION` bumps `0.X.Y → 0.X+1.0` (minor): `:0.X` stops getting new builds (frozen at last good). Users on `:0.X` see no fresh updates until they upgrade to `:0.X+1`. The immutable `:0.X.Y-<date>` tags remain pullable indefinitely.

The `:0.X.Y-YYYY-MM-DD` separator is a **hyphen**, not a dot — the dot would make the whole tag read as a four-segment version number. This matches the post-1.0 `:X.Y.Z-YYYY-MM-DD` form below.

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
KONRAD_IMAGE=ghcr.io/jlbauss/konrad:pr-42 konrad --shell    # poke around
KONRAD_IMAGE=ghcr.io/jlbauss/konrad:pr-42 konrad            # run for real
```

**PR images are a maintainer-internal convenience.** The GitHub mirror is private, so external contributors can't open PRs there — outside contributions come through **GitLab MRs** (or branches the maintainer pulls up). The `:pr-<num>` flow exists for the maintainer/collaborators with mirror access: push a feature branch to the private GitHub mirror, CI builds and publishes `:pr-<num>`, pull it to test interactively before merging on GitLab. To test an external contributor's branch this way, the maintainer pushes it to the mirror as `pr/<num>` so CI can build it; the contributor's code still runs through CI smoke regardless of where it lands.

## When to bump VERSION

**In the same PR as the change.** Reviewer verifies the bump matches the change's semver impact. A commit marked breaking (`!` or a `BREAKING CHANGE:` footer — see [CONTRIBUTING → Commit style](../../CONTRIBUTING.md#commit-style)) forces at least a MINOR bump pre-1.0, MAJOR post-1.0.

Examples:

| Change | Pre-1.0 bump | Post-1.0 bump |
| --- | --- | --- |
| Add a new bundled skill | `0.2.1 → 0.3.0` (minor) | `1.2.3 → 1.3.0` (minor) |
| Fix a bug in an existing skill with no surface change | `0.2.1 → 0.2.2` (patch) | `1.2.3 → 1.2.4` (patch) |
| Fix to `konrad --update`'s `REGISTRY_IMAGE` unbound-variable crash (no flag or output change) | `0.2.0 → 0.2.1` (patch) | `1.2.3 → 1.2.4` (patch) |
| Floating-pin refresh that pulled a security fix (daily CI) | no bump (date carries it) | no bump (date carries it) |
| Rename `konrad --shell` to `konrad --bash` | `0.2.1 → 0.3.0` (minor — no MAJOR pre-1.0) | `1.2.3 → 2.0.0` (major — breaking) |
| Add a new CLI flag | `0.2.1 → 0.3.0` (minor) | `1.2.3 → 1.3.0` (minor) |
| Update README typo | no bump | no bump |
| Update CI workflow | no bump | no bump |
| Bump Debian base from trixie to forky | `0.2.1 → 0.3.0` (minor — no MAJOR pre-1.0) | `1.2.3 → 2.0.0` (major) |

If a single PR bundles multiple concerns (rare; we prefer separate commits per concern — see CONTRIBUTING.md), the highest-impact change determines the bump.

## Git tags

- **Pre-1.0**: optional. Tag `v0.X` at moments that feel like a release. The image tag `:0.X` already serves as the immutable handle for users; the git tag is for humans navigating the history.
- **Post-1.0**: every MAJOR or MINOR release gets a git tag `vX.Y.0`. PATCH releases skip the git tag (CI tags the image, which is enough). MAJOR releases also get a GitLab Release with a written changelog.

## Releases

Releases live on **GitLab** — the primary, public repo. The GitHub mirror is a private CI execution surface only (no releases, issues, or human-facing artifacts there), and stays private for now; if it ever flips public that doesn't change where releases live.

- **Pre-1.0**: a short GitLab Release note per `v0.X` tag is nice-to-have, not required — [CHANGELOG.md](../../CHANGELOG.md) is the authoritative changelog. `v0.2` (the first public alpha) is the natural anchor for a one-paragraph "first public alpha" note.
- **Post-1.0**: for each MAJOR/MINOR — a GitLab Release titled `konrad vX.Y.0`, body with "what's new / what's broken / migration notes for breaking changes," attached to the git tag.

## Day-zero history

The pre-1.0 chapter started on **2026-05-23** with `VERSION=0.1`, when the registry-publish path went live (see ROADMAP entry of that date). Earlier development happened on `main` without a `VERSION` file and isn't representable in this scheme; the git log (and the Day-zero history below) is the authoritative record for that period.

**`0.1` is the pre-public stabilization line** — the version that existed while the repo was still private and CI / publishing / smoke gates were getting their final shakedown. Functional changes during this phase didn't always bump (the bump-in-same-PR rule itself landed mid-stream); the dated image tags `:0.1.YYYY-MM-DD` are the authoritative per-day history.

**`0.2` is the first public alpha** — shipped 2026-05-27 as the "public-alpha flip" (see [CHANGELOG.md](../../CHANGELOG.md)). "Public" means the **GitLab** repo + the GHCR package; the GitHub mirror stays private. The bump signals the regime change: from this point forward, every functional change bumps `VERSION` in its commit, and the version line a user is on actually means something to them. It's the day-one anchor for outside consumers.

**`0.2.1` is the first patch-slot bump** — landed 2026-05-29 alongside the introduction of three-segment pre-1.0 versions. Before this, `VERSION` held `0.X` and every functional change bumped `X`; the patch slot splits "bug fix with no surface change" out so `X` once again signals something meaningful to users. Existing `0.2` semantically equals `0.2.0` retroactively, but no `0.2.0` image tag was ever published — the line went `:0.2.YYYY-MM-DD` (old two-segment format, dot before date) directly to `:0.2.1-YYYY-MM-DD` (new three-segment format, hyphen before date) at the transition. The `:0.2` rolling tag's meaning carries over cleanly: it still gives users the newest passing build on the `0.2` line, now resolved through the new patch slot.
