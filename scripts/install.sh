#!/usr/bin/env bash
# Install the konrad CLI by symlinking bin/konrad into ~/.local/bin.
# Idempotent: re-running just re-points the symlink at the same source.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE="$REPO_ROOT/bin/konrad"
TARGET="${HOME}/.local/bin/konrad"

say()  { printf 'konrad-install: %s\n' "$*"; }
die()  { printf 'konrad-install: %s\n' "$*" >&2; exit 1; }

[[ -f "$SOURCE" ]] || die "expected $SOURCE to exist (is the repo intact?)"
[[ -x "$SOURCE" ]] || chmod +x "$SOURCE"

# If TARGET already exists, decide what to do:
#  - symlink pointing at SOURCE → nothing to do (or just re-link).
#  - symlink pointing elsewhere → tell the user, then overwrite.
#  - regular file → refuse, don't clobber.
if [[ -L "$TARGET" ]]; then
  current="$(readlink "$TARGET")"
  if [[ "$current" != "$SOURCE" ]]; then
    say "replacing existing symlink (was: $current)"
  fi
elif [[ -e "$TARGET" ]]; then
  die "refusing to overwrite $TARGET (exists and is not a symlink)"
fi

mkdir -p "$(dirname "$TARGET")"
ln -sfn "$SOURCE" "$TARGET"
say "linked $TARGET -> $SOURCE"

case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *)
    printf '\n'
    say "warning — $HOME/.local/bin is not in your PATH."
    say "  Add this to your shell config (~/.zshrc, ~/.bashrc, or ~/.config/fish/config.fish):"
    say "    export PATH=\"\$HOME/.local/bin:\$PATH\""
    ;;
esac
