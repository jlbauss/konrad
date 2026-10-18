# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Shared setup for the bats suites. Run them with ./scripts/check.sh tests.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
KONRAD="$REPO_ROOT/bin/konrad"

# Every test gets its own HOME, so nothing reads or writes the real ~/.config
# or ~/.local/state, and no XDG override leaks in from the caller.
setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  unset XDG_CONFIG_HOME XDG_STATE_HOME XDG_CACHE_HOME XDG_DATA_HOME
  unset KONRAD_ENGINE KONRAD_IMAGE KONRAD_DEBUG KONRAD_NO_NOTICES \
        KONRAD_NO_AUTO_REFRESH KONRAD_REFRESH_INTERVAL KONRAD_RETENTION_DAYS
  export NO_COLOR=1
}

# k '<bash snippet>': source bin/konrad's definitions (KONRAD_SOURCE_ONLY stops
# it before the flag parser) in a fresh bash and run the snippet there, under
# the `set -euo pipefail` the script itself sets — a harness without those
# options passes code that aborts in production (CLAUDE.md). The snippet can
# redefine functions first to stub the engine or the host.
k() {
  run bash -c 'KONRAD_SOURCE_ONLY=1 source "$1"; eval "$2"' _ "$KONRAD" "$1"
}
