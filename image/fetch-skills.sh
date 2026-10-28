#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Fetch the upstream skills pinned in locks/skills.lock into OUT/<name>, byte
# for byte. Runs at image-build time in the `skills` stage. Each skill is one
# shallow, blobless fetch of its pinned commit with a sparse checkout of its
# path, so a large upstream repo costs only the files of that one skill.
#
# Fails the build when a pin doesn't resolve, the path holds no SKILL.md, or
# the SKILL.md's `name:` differs from the lock's name (opencode keys a skill by
# its directory, and a mismatch would load under a name nobody asked for).
set -euo pipefail

LOCK="${1:?usage: fetch-skills.sh <skills.lock> [out dir]}"
OUT="${2:-/opt/skills}"
mkdir -p "$OUT"

die() { printf 'fetch-skills: %s\n' "$*" >&2; exit 1; }

while read -r name repo sha path extra; do
  case "$name" in ''|\#*) continue ;; esac
  [ -z "${extra:-}" ] && [ -n "${path:-}" ] || die "malformed line for '$name' (want: <name> <repo> <sha> <path>)"
  [[ "$name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || die "$name: not a valid skill name"
  [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || die "$name: '$sha' is not a full commit sha"
  [ ! -e "$OUT/$name" ] || die "$name: listed twice"

  tmp="$(mktemp -d)"
  git -C "$tmp" init -q
  git -C "$tmp" remote add origin "$repo"
  git -C "$tmp" fetch -q --depth 1 --filter=blob:none origin "$sha" \
    || die "$name: cannot fetch $sha from $repo"
  git -C "$tmp" sparse-checkout set --no-cone "/${path%/}/"
  git -C "$tmp" -c advice.detachedHead=false checkout -q FETCH_HEAD

  src="$tmp/${path%/}"
  [ -f "$src/SKILL.md" ] || die "$name: no SKILL.md at $path in $repo@$sha"
  got="$(awk 'NR == 1 && $0 != "---" { exit } NR > 1 && $0 == "---" { exit }
              NR > 1 && /^name:/ { sub(/^name:[ \t]*/, ""); gsub(/["\047 \t\r]/, ""); print; exit }' \
         "$src/SKILL.md")"
  [ "$got" = "$name" ] || die "$name: SKILL.md says name '${got:-<none>}'"

  cp -a "$src" "$OUT/$name"
  rm -rf "$tmp"
  printf 'fetch-skills: %s ← %s@%.12s:%s\n' "$name" "$repo" "$sha" "$path"
done < "$LOCK"
