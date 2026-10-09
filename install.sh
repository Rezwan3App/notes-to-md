#!/bin/bash
# notes-to-md installer for macOS
# Run: bash install.sh  (or double-click from Finder)
set -uo pipefail

echo ""
echo " ============================================"
echo "  notes-to-md installer for macOS"
echo " ============================================"
echo ""

# ── 1. Swift / Xcode Command Line Tools ────────────────────────────────────────
if command -v swift >/dev/null 2>&1; then
    echo " [1/2] Swift found."
else
    echo " [1/2] Swift not found. Launching Xcode Command Line Tools installer..."
    echo ""
    echo "  A dialog will open. Click Install, wait for it to finish,"
    echo "  then run this script again."
    echo ""
    xcode-select --install 2>/dev/null || true
    exit 0
fi

# ── 2. Copy skill to Claude skills folder ──────────────────────────────────────
DEST="$HOME/.claude/skills/notes-to-md"
SRC="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$HOME/.claude/skills"

if [ -d "$DEST" ]; then
    echo " [2/2] Updating existing skill at $DEST..."
    rm -rf "$DEST"
fi

mkdir -p "$DEST"
for f in SKILL.md README.md LICENSE; do
    [ -f "$SRC/$f" ] && cp "$SRC/$f" "$DEST/$f"
done
[ -d "$SRC/assets"  ] && cp -r "$SRC/assets"  "$DEST/assets"
[ -d "$SRC/scripts" ] && cp -r "$SRC/scripts" "$DEST/scripts"

echo ""
echo " ============================================"
echo "  Done! notes-to-md is installed."
echo " ============================================"
echo ""
echo " Restart Claude Code, then try asking:"
echo ""
echo '   "turn my handwritten notes in ~/Downloads/my-notes into markdown"'
echo ""
