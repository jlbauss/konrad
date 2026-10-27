#!/usr/bin/env bats
# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# scripts/release.sh with the real git-cliff and cliff.toml, in a throwaway repo
# whose history starts at a 0.4.2 release.

load helpers

repo() {
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.test GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.test
  R="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$R/scripts"
  cp "$REPO_ROOT/scripts/release.sh" "$R/scripts/"
  cp "$REPO_ROOT/cliff.toml" "$R/"
  git -C "$R" init -q
  printf '%s\n' '# Changelog' '' 'Intro.' '' '## [0.4.2] - 2026-01-01' '' '### Fixed' '' '- an old fix' >"$R/CHANGELOG.md"
  echo 0.4.1 >"$R/VERSION"
  commit 'chore: start'
  commit 'fix: before the last release'
  echo 0.4.2 >"$R/VERSION"
  commit 'chore(release): 0.4.2'
}

# commit '<message>': commit whatever changed, or nothing.
commit() { git -C "$R" add -A; git -C "$R" commit -q --allow-empty -m "$1"; }

@test "release.sh: fixes bump the patch and list only what users see" {
  repo
  commit 'fix(cli): resume a cut pull'
  commit 'docs: explain the pull'
  commit 'perf: start faster'
  run "$R/scripts/release.sh"
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = 0.4.3 ]
  [ "$(cat "$R/VERSION")" = 0.4.3 ]
  run sed -n '5,15p' "$R/CHANGELOG.md"
  [ "$output" = "## [0.4.3] - $(date +%F)

### Changed

- start faster

### Fixed

- resume a cut pull

## [0.4.2] - 2026-01-01" ]
}

@test "release.sh: a feat bumps the minor" {
  repo
  commit 'fix: one'
  commit 'feat(cli): konrad code up --all'
  run "$R/scripts/release.sh"
  [ "${lines[-1]}" = 0.5.0 ]
  grep -Fx -- '- konrad code up --all' "$R/CHANGELOG.md"
}

@test "release.sh: a breaking change of any type bumps the minor, marked" {
  repo
  commit 'refactor(cli)!: drop the Podman fallback on macOS'
  run "$R/scripts/release.sh"
  [ "${lines[-1]}" = 0.5.0 ]
  grep -Fx -- '- **Breaking:** drop the Podman fallback on macOS' "$R/CHANGELOG.md"
}

@test "release.sh: a BREAKING CHANGE footer bumps the minor" {
  repo
  commit 'fix: rename the flag

BREAKING CHANGE: --old is now --new'
  run "$R/scripts/release.sh"
  [ "${lines[-1]}" = 0.5.0 ]
}

@test "release.sh: nothing users see, no release" {
  repo
  commit 'docs: a doc'
  commit 'chore(locks): bump npm'
  run "$R/scripts/release.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$(git -C "$R" status --porcelain)" ]
}
