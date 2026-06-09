#!/usr/bin/env sh
# Install this org package into the konrad org config layer.
#
# Copies the org/ payload to ~/.config/konrad/org/ — the well-known location
# konrad auto-detects (no env var, no system path, no root). Idempotent:
# re-run to update. Leaves ~/.config/konrad/user/ (the user's own layer)
# untouched.
#
# This is a starting point — adapt or replace it with however your org
# distributes internal tooling (MDM, .pkg/.deb, a clone step, …). The only
# contract konrad cares about is the destination path below.
set -eu

# Resolve this script's directory so it works run from anywhere.
SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
SRC="$SCRIPT_DIR/org"
DEST="${KONRAD_CFG_DIR:-$HOME/.config/konrad}/org"

if [ ! -d "$SRC" ]; then
  echo "install.sh: payload not found at $SRC" >&2
  exit 1
fi

mkdir -p "$DEST"
# Copy the contents of org/ into the destination (not the org/ dir itself).
cp -R "$SRC/." "$DEST/"

echo "konrad org package installed → $DEST"
echo "Run 'konrad' to pick it up. Your personal layer (~/.config/konrad/user/) is unchanged."
