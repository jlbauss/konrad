#!/usr/bin/env bash
# Install the konrad CLI by symlinking bin/konrad into ~/.local/bin.
# Idempotent: re-running just re-points the symlink at the same source.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE="$REPO_ROOT/bin/konrad"
TARGET="${HOME}/.local/bin/konrad"

[[ -x "$SOURCE" ]] || chmod +x "$SOURCE"

if [[ -e "$TARGET" && ! -L "$TARGET" ]]; then
  echo "install.sh: refusing to overwrite $TARGET (not a symlink)" >&2
  exit 1
fi

mkdir -p "$(dirname "$TARGET")"
ln -sf "$SOURCE" "$TARGET"
echo "install.sh: linked $TARGET -> $SOURCE"

case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *)
    echo
    echo "install.sh: warning — $HOME/.local/bin is not in your PATH."
    echo "  Add this to your shell config (~/.zshrc, ~/.bashrc, or ~/.config/fish/config.fish):"
    echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
    ;;
esac
