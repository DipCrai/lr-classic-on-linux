#!/bin/bash
# Build fix_createwindow.dll from source.
# Usage:
#   ./build-fix_createwindow.sh              # Build Wayland version (default)
#   VARIANT=x11 ./build-fix_createwindow.sh   # Build X11 version
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
VARIANT="${VARIANT:-wayland}"
case "$VARIANT" in
    wayland) SRC="$REPO_DIR/patches/fix_createwindow.c" ;;
    x11)     SRC="$REPO_DIR/patches/fix_createwindow_x11.c" ;;
    *)
        echo "Usage: VARIANT=wayland|x11 $0"
        exit 1
        ;;
esac
if [ ! -f "$SRC" ]; then
    echo "Source not found: $SRC"
    exit 1
fi
x86_64-w64-mingw32-gcc -shared -O2 -s -o /tmp/fix_createwindow.dll "$SRC"
echo "Built: /tmp/fix_createwindow.dll ($VARIANT variant)"
