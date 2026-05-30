#!/bin/bash
BACKUP="$HOME/.steam/root/compatibilitytools.d/Proton-GE Latest/files/lib/wine/x86_64-unix/winewayland.so.backup"
TARGET="$HOME/.steam/root/compatibilitytools.d/Proton-GE Latest/files/lib/wine/x86_64-unix/winewayland.so"
if [ -f "$BACKUP" ]; then
    cp "$BACKUP" "$TARGET"
    echo "Reverted winewayland.so to original."
else
    echo "No backup found at $BACKUP"
    exit 1
fi
