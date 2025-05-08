#!/bin/bash

set -euo pipefail
trap 'echo "❌ Installation interrupted." >&2; exit 1' ERR INT

# --- Configuration ---
REPO_BASE="https://raw.githubusercontent.com/opensecurity/vmt/main"
INSTALL_DIR="$HOME/.vmt"
BIN_DIR="$HOME/.local/bin"
LINK_PATH="$BIN_DIR/vmt"

mkdir -p "$INSTALL_DIR" "$BIN_DIR"

# --- Run doctor before installing ---
echo "🧪 Running system check (vmt doctor)..."
curl -fsSL -o "$INSTALL_DIR/doctor.sh" "$REPO_BASE/doctor.sh"
chmod +x "$INSTALL_DIR/doctor.sh"
"$INSTALL_DIR/doctor.sh"

# --- Download vmt.sh ---
echo "⬇️  Downloading vmt.sh CLI script..."
curl -fsSL -o "$INSTALL_DIR/vmt.sh" "$REPO_BASE/vmt.sh"
chmod +x "$INSTALL_DIR/vmt.sh"

# --- Create symlink as `vmt` ---
echo "🔗 Creating symlink: $LINK_PATH → $INSTALL_DIR/vmt.sh"
ln -sf "$INSTALL_DIR/vmt.sh" "$LINK_PATH"

# --- Completion message ---
echo "✅ vmt installed successfully."

if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
  echo
  echo "📌 Add this to your shell config to make 'vmt' available:"
  echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

echo
echo "🚀 Try running:"
echo "  vmt help"
echo
