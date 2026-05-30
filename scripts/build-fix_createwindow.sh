#!/bin/bash
# Build fix_createwindow.dll from repo source
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC="$REPO_DIR/patches/fix_createwindow.c"
OUT="${OUT:-/tmp/fix_createwindow.dll}"

if ! command -v x86_64-w64-mingw32-gcc &>/dev/null; then
    echo "ERROR: x86_64-w64-mingw32-gcc not found."
    echo "Install: sudo dnf install mingw64-gcc (Fedora) or apt install mingw-w64 (Debian)"
    exit 1
fi

if [ ! -f "$SRC" ]; then
    echo "ERROR: Source not found at $SRC"
    exit 1
fi

x86_64-w64-mingw32-gcc -shared -O2 -s -o "$OUT" "$SRC" 2>&1
if [ $? -eq 0 ]; then
    echo "OK: $OUT ($(stat -c%s "$OUT") bytes)"
else
    echo "Build failed"
    exit 1
fi
