#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Update rehearsal: upgrade the previous release's CLI to this checkout the way
# a user's `konrad update` and background refresh do, against a local registry
# instead of ghcr.io and a local file tree instead of the forge.
#
#     konrad-dev rebuild && ./scripts/test-autoupdate.sh [<prev-tag>] [<image>]
#
# <prev-tag> defaults to the newest v* tag that isn't this checkout's VERSION;
# <image> to konrad:local, the fresh build that plays the published :latest.
#
# What it proves, each step asserted:
#   1. `konrad update` from <prev-tag>'s CLI installs this checkout's CLI with
#      its version baked in, pulls the registry's :latest into konrad:latest,
#      and re-syncs an org layer to its newest commit; the user layer survives.
#   2. A normal start works on the updated install (`konrad opencode --version`,
#      firewall on).
#   3. The background refresh pulls a newer :latest on its own, and the next
#      launch announces it.
#
# Nothing touches the real install: HOME is a temp dir, the old CLI is a copy
# whose INSTALL_URL points at a copy of scripts/install.sh, whose base URL
# points at this checkout's files (each rewrite asserted). The engine's store
# is shared, so an existing konrad:latest tag is restored at the end; the
# pulled layers are konrad:local's, so they cost no extra disk. Podman only.
set -euo pipefail

cd "$(dirname "$0")/.."

pass() { printf '  \033[32mPASS\033[0m  %s\n' "$*"; }
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$*" >&2; exit 1; }
info() { printf '\n\033[1m%s\033[0m\n' "$*"; }

NEW_VERSION="$(cat VERSION)"
PREV_TAG="${1:-$(git tag --list 'v*' --sort=-v:refname | grep -vx "v$NEW_VERSION" | head -n 1)}"
IMAGE="${2:-konrad:local}"
PREV_VERSION="${PREV_TAG#v}"
[[ -n "$PREV_TAG" ]] || fail "no previous release tag found (git fetch --tags?)"
git rev-parse --verify --quiet "$PREV_TAG^{commit}" >/dev/null || fail "unknown tag $PREV_TAG"
podman image exists "$IMAGE" || fail "$IMAGE not found — run konrad-dev rebuild first"

T="$(mktemp -d)"
REG_NAME="konrad-rehearsal-registry-$$"
OLD_LATEST="$(podman image inspect --format '{{.Id}}' konrad:latest 2>/dev/null || true)"
cleanup() {
  podman rm -f "$REG_NAME" >/dev/null 2>&1 || true
  podman rmi konrad-rehearsal:old konrad-rehearsal:newer >/dev/null 2>&1 || true
  if [[ -n "$OLD_LATEST" ]]; then
    podman tag "$OLD_LATEST" konrad:latest >/dev/null 2>&1 || true
  else
    podman untag konrad:latest >/dev/null 2>&1 || true
  fi
  rm -rf "$T"
}
trap cleanup EXIT

# Replace one exact string in a file, failing when it isn't there exactly once:
# a rewrite that silently misses would test the real forge instead.
rewrite() {
  local file="$1" old="$2" new="$3"
  OLD="$old" NEW="$new" python3 - "$file" <<'PY' || fail "rewrite of '$2' in $1 didn't match exactly once"
import os, sys
p = sys.argv[1]; s = open(p).read(); old = os.environ["OLD"]
if s.count(old) != 1:
    sys.exit(1)
open(p, "w").write(s.replace(old, os.environ["NEW"]))
PY
}

info "rehearsal: $PREV_TAG → $NEW_VERSION (image $IMAGE)"

# --- A local registry playing ghcr.io --------------------------------------------
podman run -d --rm --name "$REG_NAME" -p 127.0.0.1::5000 docker.io/library/registry:2 >/dev/null
REG="$(podman port "$REG_NAME" 5000/tcp | head -n 1)"
[[ "$REG" == 127.0.0.1:* ]] || fail "registry port not published ($REG)"
for _ in $(seq 1 30); do curl -fs "http://$REG/v2/" >/dev/null && break; sleep 1; done
curl -fs "http://$REG/v2/" >/dev/null || fail "registry didn't come up"
# Plain HTTP on loopback: tell every podman call below (konrad's included) so.
printf '[[registry]]\nlocation = "%s"\ninsecure = true\n' "$REG" > "$T/registries.conf"
export CONTAINERS_REGISTRIES_CONF="$T/registries.conf"
podman push --quiet "$IMAGE" "$REG/konrad:latest" >/dev/null
NEW_ID="$(podman image inspect --format '{{.Id}}' "$IMAGE")"
pass "registry at $REG serves $IMAGE as :latest"

# --- The previous release's install -----------------------------------------------
# Its image: the fresh build relabelled, so it has a different ID.
printf 'FROM %s\nLABEL org.opencontainers.image.version="%s"\n' "$IMAGE" "$PREV_VERSION" \
  | podman build --quiet -t konrad-rehearsal:old -f - "$T" >/dev/null
podman tag konrad-rehearsal:old konrad:latest
OLD_ID="$(podman image inspect --format '{{.Id}}' konrad:latest)"
[[ "$OLD_ID" != "$NEW_ID" ]] || fail "stand-in old image has the new image's ID"

# What the installer will fetch: this checkout's CLI and VERSION, served as files.
mkdir -p "$T/serve/main/bin"
cp bin/konrad "$T/serve/main/bin/konrad"
cp VERSION "$T/serve/main/VERSION"
cp scripts/install.sh "$T/install.sh"
rewrite "$T/install.sh" 'BASE_URL_DEFAULT="https://gitlab.git.nrw/jbauss2/konrad/-/raw"' \
                        "BASE_URL_DEFAULT=\"file://$T/serve\""

# The old CLI, installed the way install.sh does it, pointed at that installer.
export HOME="$T/home"
unset XDG_CONFIG_HOME XDG_STATE_HOME XDG_CACHE_HOME XDG_DATA_HOME KONRAD_IMAGE
BIN="$HOME/.local/bin"
mkdir -p "$BIN"
git show "$PREV_TAG:bin/konrad" > "$BIN/konrad"
rewrite "$BIN/konrad" 'KONRAD_VERSION_BAKED=""' "KONRAD_VERSION_BAKED=\"$PREV_VERSION\""
rewrite "$BIN/konrad" 'INSTALL_URL="https://gitlab.git.nrw/jbauss2/konrad/-/raw/main/scripts/install.sh"' \
                      "INSTALL_URL=\"file://$T/install.sh\""
chmod +x "$BIN/konrad"
export PATH="$BIN:$PATH" KONRAD_REGISTRY_IMAGE="$REG/konrad:latest" KONRAD_DESKTOP=0 NO_COLOR=1

# State the update must keep: a user layer, and an org layer one commit behind.
mkdir -p "$HOME/.config/konrad/user"
echo '{ "env": { "REHEARSAL_USER": "kept" } }' > "$HOME/.config/konrad/user/opencode.jsonc"
git init --quiet --bare "$T/org.git"
git clone --quiet "$T/org.git" "$T/org-work" 2>/dev/null
git -C "$T/org-work" -c user.name=r -c user.email=r@example.invalid commit --quiet --allow-empty -m one
git -C "$T/org-work" push --quiet origin HEAD 2>/dev/null
konrad org add "file://$T/org.git" --name rehearsal 2>/dev/null
git -C "$T/org-work" -c user.name=r -c user.email=r@example.invalid commit --quiet --allow-empty -m two
git -C "$T/org-work" push --quiet origin HEAD 2>/dev/null
ORG_HEAD="$(git -C "$T/org-work" rev-parse HEAD)"

# Baseline: the old release is what's installed and running.
konrad --version > "$T/before" 2>&1 || { cat "$T/before"; fail "old CLI --version failed"; }
grep -F "cli:    $PREV_VERSION" "$T/before" >/dev/null || { cat "$T/before"; fail "baseline isn't $PREV_VERSION"; }
pass "baseline: $PREV_TAG installed as konrad, on the old image, org layer one commit behind"

# --- 1. konrad update ---------------------------------------------------------------
info "konrad update"
konrad update > "$T/update.log" 2>&1 || { cat "$T/update.log"; fail "konrad update exited non-zero"; }
grep -F "KONRAD_VERSION_BAKED=\"$NEW_VERSION\"" "$BIN/konrad" >/dev/null \
  || fail "installed CLI doesn't carry $NEW_VERSION"
cmp -s <(sed "s|^KONRAD_VERSION_BAKED=\"$NEW_VERSION\"|KONRAD_VERSION_BAKED=\"\"|" "$BIN/konrad") bin/konrad \
  || fail "installed CLI isn't this checkout's bin/konrad"
konrad --version > "$T/after" 2>&1
grep -F "cli:    $NEW_VERSION" "$T/after" >/dev/null || { cat "$T/after"; fail "--version doesn't report $NEW_VERSION"; }
pass "CLI is this checkout's, version $NEW_VERSION baked"
[[ "$(podman image inspect --format '{{.Id}}' konrad:latest)" == "$NEW_ID" ]] \
  || fail "konrad:latest isn't the registry's :latest"
pass "konrad:latest is the registry's image"
[[ "$(git -C "$HOME/.config/konrad/org/rehearsal" rev-parse HEAD)" == "$ORG_HEAD" ]] \
  || fail "org layer wasn't synced to its newest commit"
grep -F '"kept"' "$HOME/.config/konrad/user/opencode.jsonc" >/dev/null || fail "user layer changed"
pass "org layer synced, user layer kept"

# --- 2. a normal start ------------------------------------------------------------------
info "normal start"
KONRAD_NO_AUTO_REFRESH=1 konrad opencode --version > "$T/start.log" 2>&1 \
  || { cat "$T/start.log"; fail "konrad opencode --version failed"; }
grep -E '^[0-9]+\.[0-9]+\.[0-9]+' "$T/start.log" >/dev/null || { cat "$T/start.log"; fail "no opencode version printed"; }
pass "konrad opencode --version runs on the updated install ($(grep -E '^[0-9]+\.' "$T/start.log" | head -n 1))"

# --- 3. the background refresh -------------------------------------------------------
info "background refresh"
printf 'FROM %s\nLABEL io.konrad.rehearsal="newer"\n' "$IMAGE" \
  | podman build --quiet -t konrad-rehearsal:newer -f - "$T" >/dev/null
NEWER_ID="$(podman image inspect --format '{{.Id}}' konrad-rehearsal:newer)"
podman push --quiet konrad-rehearsal:newer "$REG/konrad:latest" >/dev/null
STATE="$HOME/.local/state/konrad"
echo 0 > "$STATE/last-refresh"     # an old stamp, so the next launch refreshes
rm -f "$STATE/refresh.log"
konrad opencode --version > "$T/fire.log" 2>&1 || { cat "$T/fire.log"; fail "launch that fires the refresh failed"; }
for _ in $(seq 1 300); do
  [[ -f "$STATE/refresh.log" ]] && grep -F '=== refresh done' "$STATE/refresh.log" >/dev/null && break
  sleep 1
done
grep -F '=== refresh done' "$STATE/refresh.log" >/dev/null 2>&1 \
  || { cat "$STATE/refresh.log" 2>/dev/null; fail "background refresh didn't finish in 300 s"; }
[[ "$(podman image inspect --format '{{.Id}}' konrad:latest)" == "$NEWER_ID" ]] \
  || { cat "$STATE/refresh.log"; fail "background refresh didn't move konrad:latest"; }
pass "background refresh pulled the newer :latest"
KONRAD_NO_AUTO_REFRESH=1 konrad opencode --version > "$T/next.log" 2>&1 || { cat "$T/next.log"; fail "next launch failed"; }
grep -F 'updated to a newer image in the background' "$T/next.log" >/dev/null \
  || { cat "$T/next.log"; fail "next launch didn't announce the new image"; }
pass "the next launch announces it"

printf '\n\033[32mupdate rehearsal passed: %s → %s\033[0m\n' "$PREV_TAG" "$NEW_VERSION"
