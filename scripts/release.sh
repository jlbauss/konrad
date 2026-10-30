#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Prepare the next release from the commits since the last one: bump VERSION
# and add its CHANGELOG.md section, written by git-cliff (cliff.toml). The
# release-mr job in .gitlab-ci.yml runs it after every merge to main and lands
# the result as `chore(release): <version>`; the release job then tags it.
#
#     scripts/release.sh                    # prints the new version, or nothing to release
#     scripts/release.sh --preview [<base>] # prints the section a merge would add, changes nothing
#
# --preview takes the commits since <base> (default origin/main) instead: the
# release notes of a branch, for its merge request description (CLAUDE.md).
#
# The last release is the last commit that changed VERSION, not the last tag,
# so a release whose tag the release job hasn't cut yet still counts. The bump
# follows CONTRIBUTING → Versioning: a feat or a breaking change (`!`, or a
# BREAKING CHANGE footer) bumps the minor, a fix or perf the patch, and any
# other type releases nothing.
set -euo pipefail

cd "$(dirname "$0")/.."
GIT_CLIFF="${GIT_CLIFF:-uv tool run --quiet --from git-cliff==2.14.2 git-cliff}"

if [[ "${1:-}" == --preview ]]; then
  preview=1 base="${2:-origin/main}"
else
  preview=0 base="$(git log -1 --format=%H -- VERSION)"
fi
[[ -n "$base" ]] || { echo "release.sh: no commit has changed VERSION" >&2; exit 1; }
subjects="$(git log --format=%s "$base..HEAD")"
bodies="$(git log --format=%b "$base..HEAD")"
IFS=. read -r major minor patch <VERSION

if grep -E '^[a-z]+(\([^)]*\))?!:' <<<"$subjects" >/dev/null \
  || grep -E '^BREAKING[ -]CHANGE:' <<<"$bodies" >/dev/null \
  || grep -E '^feat(\([^)]*\))?:' <<<"$subjects" >/dev/null; then
  version="$major.$((minor + 1)).0"
elif grep -E '^(fix|perf)(\([^)]*\))?:' <<<"$subjects" >/dev/null; then
  version="$major.$minor.$((patch + 1))"
else
  exit 0
fi

# The new section goes above the newest one.
section="$($GIT_CLIFF --config cliff.toml --tag "v$version" "$base..HEAD" | sed '/./,$!d')"
[[ "$section" == "## [$version] - "* ]] || { echo "release.sh: git-cliff wrote no section for $version" >&2; exit 1; }
if ((preview)); then
  echo "$section"
  exit 0
fi
section="$section" awk '!done && /^## \[/ { print ENVIRON["section"]; print ""; done = 1 } { print }' \
  CHANGELOG.md >CHANGELOG.md.new
mv CHANGELOG.md.new CHANGELOG.md
echo "$version" >VERSION
echo "$version"
