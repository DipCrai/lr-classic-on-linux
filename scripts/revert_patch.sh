#!/bin/bash
# Revert the winewayland.so binary patch.
# Usage:
#   ./revert_patch.sh                          # Revert default Proton path
#   PROTON_DIR=/path ./revert_patch.sh          # Custom Proton path
set -e
PROTON_DIR="${PROTON_DIR:-$HOME/.steam/root/compatibilitytools.d/Proton-GE Latest}"
BACKUP="$PROTON_DIR/files/lib/wine/x86_64-unix/winewayland.so.backup"
TARGET="$PROTON_DIR/files/lib/wine/x86_64-unix/winewayland.so"
OFFSET=0x12efe
# First 10 bytes of the patch (mov + call) — enough to confirm patch is applied
PATCH_MARKER="4889de4c89e7e8572901"

if [ ! -f "$TARGET" ]; then
    echo "Error: $TARGET not found."
    echo "Set PROTON_DIR to your GE-Proton installation directory."
    exit 1
fi

# Read current bytes at patch offset (plain hex, no spaces/newlines)
CURRENT=$(od -A n -t x1 -j $OFFSET -N 10 "$TARGET" | tr -d ' \n')
if [ "$CURRENT" != "$PATCH_MARKER" ]; then
    echo "Patch is not currently applied at offset $OFFSET."
    echo "Found:   $CURRENT"
    echo "Expected: $PATCH_MARKER (first 10 bytes of patch)"
    echo "If you need to restore from backup: cp \"$BACKUP\" \"$TARGET\""
    exit 1
fi

if [ ! -f "$BACKUP" ]; then
    echo "No backup found at $BACKUP"
    echo "Cannot revert — original file is unknown."
    echo "Try reinstalling GE-Proton to restore the original."
    exit 1
fi

# Sanity check: backup must differ from patched file
if cmp -s "$BACKUP" "$TARGET"; then
    echo "ERROR: Backup is identical to patched file. Backup may have been overwritten."
    echo "Cannot safely revert."
    exit 1
fi

cp "$BACKUP" "$TARGET"
echo "Reverted winewayland.so to original (from backup)."
