#!/bin/bash
# Revert the winewayland.so binary patch.
# Usage:
#   ./revert_patch.sh                          # Revert default Proton path
#   PROTON_DIR=/path ./revert_patch.sh          # Custom Proton path
set -e
PROTON_DIR="${PROTON_DIR:-$HOME/.steam/root/compatibilitytools.d/Proton-GE Latest}"
BACKUP="$PROTON_DIR/files/lib/wine/x86_64-unix/winewayland.so.backup"
TARGET="$PROTON_DIR/files/lib/wine/x86_64-unix/winewayland.so"
if [ -f "$BACKUP" ]; then
    cp "$BACKUP" "$TARGET"
    echo "Reverted winewayland.so to original."
else
    echo "No backup found at $BACKUP"
    exit 1
fi
