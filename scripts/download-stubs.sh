#!/bin/bash
# Download CC stub DLLs from sander110419/lightroom-cc-on-linux.
# Usage: ./download-stubs.sh [output_dir]
#   output_dir  - directory to save DLLs (default: ./stubs/)
set -e
BASE_URL="https://raw.githubusercontent.com/sander110419/lightroom-cc-on-linux/main/stubs/binaries"
OUT_DIR="${1:-$(cd "$(dirname "$0")/.." && pwd)/stubs}"
mkdir -p "$OUT_DIR"

FILES="
d2d1-patched.dll:d2d1.dll
mfplat-patched.dll:mfplat.dll
adobe_e26b366d-stub.dll:adobe_e26b366d.dll
thumbcache-stub.dll:thumbcache.dll
hnetcfg-stub.dll:hnetcfg.dll
ext-ms-win-uiacore-l1-1-2.dll:ext-ms-win-uiacore-l1-1-2.dll
NDFAPI.DLL:NDFAPI.DLL
wkscli.dll:wkscli.dll
"

for entry in $FILES; do
    src="${entry%%:*}"
    dst="${entry##*:}"
    url="$BASE_URL/$src"
    echo "Downloading $src → $OUT_DIR/$dst"
    if curl -sLf "$url" -o "$OUT_DIR/$dst"; then
        echo "  OK ($(stat -c%s "$OUT_DIR/$dst") bytes)"
    else
        echo "  FAILED: $url"
    fi
done
echo "Done. Stubs in: $OUT_DIR"
