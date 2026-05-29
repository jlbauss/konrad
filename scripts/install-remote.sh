#!/usr/bin/env sh
# konrad — frictionless installer. Drops the CLI on PATH (no clone needed)
# and, by default, pre-pulls the container image so the next `konrad` run
# is instant.
#
# Usage (one-liner):
#   curl -fsSL https://gitlab.git.nrw/jbauss2/konrad/-/raw/main/scripts/install-remote.sh | sh
#
# Knobs (env vars):
#   KONRAD_INSTALL_DIR     target directory (default: $HOME/.local/bin)
#   KONRAD_NO_PULL=1       skip the post-install `konrad --update` (CLI only)
#   KONRAD_QUIET_INSTALL=1 suppress play-by-play (fetching… / skip notices);
#                          keep the one "installed …" confirmation. Set by
#                          `konrad --update` since the caller already framed
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

say()  { printf 'konrad-install: %s\n' "$*"; }
warn() { printf 'konrad-install: warning: %s\n' "$*" >&2; }
die()  { printf 'konrad-install: %s\n' "$*" >&2; exit 1; }
# chatter() is for play-by-play that's useful in a standalone `curl|sh` run
# but redundant when re-invoked from `konrad --update` (the caller already
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
say "installed $TARGET (konrad $VER)"

# --- PATH advice -------------------------------------------------------------
case ":$PATH:" in
  *":$TARGET_DIR:"*) ;;
  *)
    printf '\n'
    warn "$TARGET_DIR is not in your PATH."
    say  "  Add this to your shell config (~/.zshrc, ~/.bashrc, or ~/.config/fish/config.fish):"
    say  "    export PATH=\"$TARGET_DIR:\$PATH\""
    printf '\n'
    ;;
esac

# --- Podman preflight (warn-only) -------------------------------------------
if ! command -v podman >/dev/null 2>&1; then
  warn "podman is not installed. konrad needs it at runtime."
  say  "  macOS:  brew install podman && podman machine init && podman machine start"
  say  "  Linux:  see https://podman.io/docs/installation"
  say  "Install podman and re-run; the CLI is already in place."
  exit 0
fi

# --- Pre-pull the image ------------------------------------------------------
# The pull goes through the freshly-installed `konrad --pull-image` rather
# than a bare `podman pull` so the layer counter (jq + curl manifest
# preflight + awk wrapper) has one implementation. KONRAD_NO_PULL=1 is set
# by `konrad --update` when it re-runs this installer for the CLI refresh —
# in that case the caller already pulled and already prints --version, so
# both steps are short-circuited.
if [ "${KONRAD_NO_PULL:-0}" = "1" ]; then
  chatter "skipping image pre-pull (KONRAD_NO_PULL=1). Run 'konrad --update' when ready."
  exit 0
fi

if ! podman info >/dev/null 2>&1; then
  warn "podman is installed but not reachable (VM not started? socket missing?)."
  say  "  On macOS:  podman machine init && podman machine start"
  say  "Skipping pre-pull. Run 'konrad --update' once podman is up."
  exit 0
fi

if ! "$TARGET" --pull-image; then
  warn "image pre-pull failed; konrad will retry on first run."
fi

printf '\n'
"$TARGET" --version || true
say "done. Run: konrad"
