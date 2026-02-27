#!/usr/bin/env bash
# Install d into a directory on $PATH.
# Usage:  ./install.sh [dest-dir]
# Default dest-dir: /usr/local/bin

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${SCRIPT_DIR}/d"
DEST_DIR="${1:-/usr/local/bin}"

if [[ ! -f "$SRC" ]]; then
    echo "error: source script not found: $SRC" >&2
    exit 1
fi

# Create destination directory if needed
if [[ ! -d "$DEST_DIR" ]]; then
    echo "Creating directory: $DEST_DIR"
    mkdir -p "$DEST_DIR"
fi

DEST="${DEST_DIR}/d"

# Use a symlink so updates to the repo are reflected immediately
if ln -sf "$SRC" "$DEST" 2>/dev/null; then
    echo "Linked:  $SRC → $DEST"
else
    # May need sudo for /usr/local/bin
    echo "Trying with sudo..."
    sudo ln -sf "$SRC" "$DEST"
    echo "Linked:  $SRC → $DEST  (via sudo)"
fi

echo ""
echo "Installation complete.  Try:  d --help"

# Warn if dest dir is not on PATH
if ! echo "$PATH" | tr ':' '\n' | grep -qx "$DEST_DIR"; then
    echo ""
    echo "Warning: $DEST_DIR is not in your \$PATH."
    echo "         Add this line to your shell profile (~/.zshrc or ~/.bashrc):"
    echo ""
    echo "         export PATH=\"\$PATH:${DEST_DIR}\""
fi

# Recommend fzf if not present
if ! command -v fzf &>/dev/null; then
    echo ""
    echo "Tip: Install fzf for a better multi-container selection experience:"
    echo "     brew install fzf"
fi
