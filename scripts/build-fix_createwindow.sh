#!/bin/bash
# Build the fix_createwindow.dll from source
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$SCRIPT_DIR/../patches/fix_createwindow.c"
OUT="/tmp/fix_createwindow.dll"

if ! command -v x86_64-w64-mingw32-gcc &>/dev/null; then
    echo "ERROR: x86_64-w64-mingw32-gcc not found. Install mingw-w64-gcc."
    exit 1
fi

x86_64-w64-mingw32-gcc -shared -O2 -s -o "$OUT" "$SRC" 2>&1
if [ $? -eq 0 ]; then
    echo "Built: $OUT ($(stat -c%s "$OUT") bytes)"
else
    echo "Build failed"
    exit 1
fi
