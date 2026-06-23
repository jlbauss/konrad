#!/usr/bin/env sh
# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
# konrad — frictionless installer. Drops the CLI on PATH (no clone needed)
# and, by default, pre-pulls the container image so the next `konrad` run
# is instant.
#
# Usage (one-liner):
#   curl -fsSL https://gitlab.git.nrw/jbauss2/konrad/-/raw/main/scripts/install.sh | sh
#
# Knobs (env vars):
#   KONRAD_INSTALL_DIR     target directory (default: $HOME/.local/bin)
#   KONRAD_NO_PULL=1       install the CLI only — skip the image pre-pull.
#                          (`konrad update` does NOT set this; it lets the
#                          installer own the pull so there's one pull path.)
#   KONRAD_QUIET_INSTALL=1 suppress play-by-play (fetching… / skip notices);
#                          keep the one "installed …" confirmation. Set by
#                          `konrad update` since the caller already framed
#                          the operation.
#   KONRAD_REF=main        git ref on gitlab.git.nrw/jbauss2/konrad to fetch from
#
# Re-run any time to upgrade in place. Hacking on konrad itself? Clone
# the repo and symlink bin/konrad as `konrad-dev` next to your stable
# konrad — see CONTRIBUTING.md for the full contributor setup.
#
# Written in POSIX sh on purpose: `curl | sh` users may not have bash.
set -eu

BASE_URL_DEFAULT="https://gitlab.git.nrw/jbauss2/konrad/-/raw"
REF="${KONRAD_REF:-main}"
BASE_URL="${BASE_URL_DEFAULT}/${REF}"
CLI_URL="${BASE_URL}/bin/konrad"
VERSION_URL="${BASE_URL}/VERSION"

# Output style — mirrors bin/konrad's helpers (a dim `konrad` prefix; colored
# warning/error tags; ✓/→ glyphs for the completed-step / handoff lines) so the
# install reads as one continuous styled sequence with the CLI and the in-
# container entrypoint. Color is gated on an interactive stderr with NO_COLOR
# unset, so a piped `curl|sh` or the `konrad update` re-invocation stays plain.
# POSIX sh has no $'\033' ANSI-C quoting, so the ESC byte comes from printf.
if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
  _ESC=$(printf '\033')
  _C_OK="${_ESC}[32m"; _C_GO="${_ESC}[36m"; _C_WARN="${_ESC}[33m"
  _C_ERR="${_ESC}[31m"; _C_DIM="${_ESC}[2m";  _C_OFF="${_ESC}[0m"
else
  _C_OK=''; _C_GO=''; _C_WARN=''; _C_ERR=''; _C_DIM=''; _C_OFF=''
fi

# All messages go to stderr; like the CLI, nothing here is "tool output".
say()  { printf '%skonrad%s %s\n'              "$_C_DIM" "$_C_OFF" "$*" >&2; }
warn() { printf '%skonrad%s %swarning:%s %s\n' "$_C_DIM" "$_C_OFF" "$_C_WARN" "$_C_OFF" "$*" >&2; }
die()  { printf '%skonrad%s %serror:%s %s\n'   "$_C_DIM" "$_C_OFF" "$_C_ERR" "$_C_OFF" "$*" >&2; exit 1; }
step() { printf '  %s✓%s  %s\n'                "$_C_OK"  "$_C_OFF" "$*" >&2; }
go()   { printf '  %s→%s  %s\n'                "$_C_GO"  "$_C_OFF" "$*" >&2; }
# chatter() is for play-by-play that's useful in a standalone `curl|sh` run
# but redundant when re-invoked from `konrad update` (the caller already
# said "refreshing CLI"). Honors KONRAD_QUIET_INSTALL=1.
chatter() { [ "${KONRAD_QUIET_INSTALL:-0}" = "1" ] || say "$@"; }

# --- Pick a download tool ----------------------------------------------------
if command -v curl >/dev/null 2>&1; then
  fetch() { curl -fsSL "$1"; }
elif command -v wget >/dev/null 2>&1; then
  fetch() { wget -qO- "$1"; }
else
  die "neither curl nor wget is installed; cannot fetch konrad."
fi

# --- Pick a target directory -------------------------------------------------
# Priority: $KONRAD_INSTALL_DIR → $HOME/.local/bin (created if missing) →
# /usr/local/bin if writable. We never sudo automatically.
TARGET_DIR="${KONRAD_INSTALL_DIR:-}"
if [ -z "$TARGET_DIR" ]; then
  if mkdir -p "$HOME/.local/bin" 2>/dev/null; then
    TARGET_DIR="$HOME/.local/bin"
  elif [ -w /usr/local/bin ]; then
    TARGET_DIR="/usr/local/bin"
  else
    die "couldn't create $HOME/.local/bin and /usr/local/bin isn't writable. Set KONRAD_INSTALL_DIR to a writable dir."
  fi
else
  mkdir -p "$TARGET_DIR" || die "couldn't create $TARGET_DIR"
fi
TARGET="${TARGET_DIR}/konrad"

# --- Fetch VERSION + CLI -----------------------------------------------------
chatter "fetching VERSION from $VERSION_URL"
VER=$(fetch "$VERSION_URL") || die "failed to fetch VERSION (network? wrong ref '$REF'?)"
[ -n "$VER" ] || die "fetched empty VERSION; aborting."

chatter "fetching CLI from $CLI_URL"
TMP=$(mktemp 2>/dev/null || mktemp -t konrad-install)
trap 'rm -f "$TMP" "$TMP.baked"' EXIT INT TERM
fetch "$CLI_URL" > "$TMP" || die "failed to fetch bin/konrad"
[ -s "$TMP" ] || die "fetched empty bin/konrad; aborting."

# Sanity-check that we actually fetched bin/konrad and not e.g. an HTML
# error page from the raw-url host. Cheap and high-signal.
if ! head -1 "$TMP" | grep -q '^#!/usr/bin/env bash$'; then
  die "fetched file doesn't look like bin/konrad (wrong shebang). Check that $CLI_URL resolves to the script."
fi
if ! grep -q 'KONRAD_VERSION_BAKED=' "$TMP"; then
  die "fetched bin/konrad lacks the KONRAD_VERSION_BAKED hook — installer and CLI versions are out of sync. Re-run later or pin KONRAD_REF."
fi

# --- Bake the version in ----------------------------------------------------
# The CLI's version-discovery prefers $REPO_ROOT/VERSION (clone path); when
# that's missing it falls back to KONRAD_VERSION_BAKED. Rewriting the
# placeholder here means standalone-installed CLIs report the real number.
# Use a temp char (|) as the sed delimiter since version strings shouldn't
# contain it; escape just in case.
SAFE_VER=$(printf '%s' "$VER" | sed 's/[|\\&]/\\&/g')
sed "s|^KONRAD_VERSION_BAKED=\"\"|KONRAD_VERSION_BAKED=\"${SAFE_VER}\"|" "$TMP" > "$TMP.baked" \
  || die "failed to bake VERSION into bin/konrad."
# Verify the substitution actually fired — silent failure would leave us
# shipping a CLI that reports "dev" forever.
if ! grep -q "^KONRAD_VERSION_BAKED=\"${VER}\"" "$TMP.baked"; then
  die "VERSION bake didn't take effect. The fetched CLI's placeholder may have changed shape."
fi

# --- Refuse to clobber unrelated files --------------------------------------
# If $TARGET already exists, allow overwrite only if it looks like a
# previous konrad install (or a dangling symlink — those are safe to nuke).
if [ -L "$TARGET" ] && [ ! -e "$TARGET" ]; then
  : # dangling symlink, fine to replace
elif [ -e "$TARGET" ]; then
  if ! grep -q 'konrad — sandboxed opencode' "$TARGET" 2>/dev/null; then
    die "refusing to overwrite $TARGET (exists, doesn't look like a previous konrad install). Set KONRAD_INSTALL_DIR or remove it manually."
  fi
fi

install -m 0755 "$TMP.baked" "$TARGET" 2>/dev/null \
  || { cp "$TMP.baked" "$TARGET" && chmod 0755 "$TARGET"; } \
  || die "failed to install $TARGET"
step "installed $TARGET (konrad $VER)"

# --- PATH advice -------------------------------------------------------------
case ":$PATH:" in
  *":$TARGET_DIR:"*) ;;
  *)
    printf '\n' >&2
    warn "$TARGET_DIR is not in your PATH."
    say  "  Add this to your shell config (~/.zshrc, ~/.bashrc, or ~/.config/fish/config.fish):"
    say  "    export PATH=\"$TARGET_DIR:\$PATH\""
    printf '\n' >&2
    ;;
esac

# --- Pre-pull the image (delegated to the freshly-installed CLI) -------------
# One source of truth, and the answer to "why doesn't the installer start the
# engine like the CLI does": it now uses the CLI's path. `konrad pull-image`
# already detects the engine, starts it when it can (podman machine / container
# system start, via require_engine → eng_try_start — exactly what a normal run
# does), and prints tailored guidance when it can't (engine missing or a Podman
# VM not yet initialized). So the installer no longer duplicates engine
# detection, install hints, or a warn-only "not running" branch — it asks the
# CLI, which is what the user's first real run would do anyway.
#
# KONRAD_NO_PULL=1 installs the CLI only. `konrad update` does NOT set it (it
# wants the installer to own the pull); it's a knob for a deliberately CLI-only
# install. A failed/blocked pre-pull is non-fatal: the CLI is already in place
# and will pull on first run, so we note it and exit 0.
if [ "${KONRAD_NO_PULL:-0}" = "1" ]; then
  chatter "skipping image pre-pull (KONRAD_NO_PULL=1). Run 'konrad update' when ready."
  exit 0
fi

if ! "$TARGET" pull-image; then
  warn "image pre-pull didn't complete; konrad will pull it on first run."
fi

printf '\n' >&2
"$TARGET" --version || true
go "done. Run: konrad"
