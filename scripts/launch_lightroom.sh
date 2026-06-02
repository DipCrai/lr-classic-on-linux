#!/bin/bash
# Lightroom Classic on Linux — Wayland launcher (GPU pref trick makes histogram work)
# Source: https://github.com/DipCrai/lr-classic-on-linux
set -o pipefail

# ========== CONFIGURATION ==========
LR_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WINEPREFIX="${WINEPREFIX:-$HOME/.lightroom_prefix/pfx}"
STEAM_COMPAT_DATA_PATH="${STEAM_COMPAT_DATA_PATH:-$HOME/.lightroom_prefix}"
STEAM_COMPAT_CLIENT_INSTALL_PATH="${STEAM_COMPAT_CLIENT_INSTALL_PATH:-$HOME/.steam/root}"
PROTON_DIR="${PROTON_DIR:-$STEAM_COMPAT_CLIENT_INSTALL_PATH/compatibilitytools.d/Proton-GE Latest}"
LR_EXE="${LR_EXE:-$LR_DIR/Lightroom.exe}"
DXVK_CONF="${DXVK_CONF:-$LR_DIR/dxvk.conf}"
# Auto-detect monitor name, fallback to HDMI-A-1
if [ -z "${MONITOR:-}" ]; then
    MONITOR=$(wlr-randr 2>/dev/null | grep -m1 '^[A-Z]' | awk '{print $1}') || MONITOR="HDMI-A-1"
fi
LOG_DIR="${LOG_DIR:-/tmp/proton_logs}"
PATCH_SOURCE="${PATCH_SOURCE:-$LR_DIR/patches/fix_createwindow.c}"
SCRIPTS_DIR="$(dirname "$0")"

# Validate Lightroom executable
if [ ! -f "$LR_EXE" ]; then
    echo "ERROR: Lightroom executable not found at: $LR_EXE"
    echo "Set LR_EXE to your Lightroom.exe path, e.g.:"
    echo "  LR_EXE=/path/to/Lightroom.exe ./scripts/launch_lightroom.sh"
    echo "  LR_DIR=/path/to/lightroom ./scripts/launch_lightroom.sh"
    exit 1
fi

if [ ! -f "$DXVK_CONF" ]; then
    echo "WARNING: dxvk.conf not found at $DXVK_CONF"
fi

mkdir -p "$LOG_DIR"

# ========== FIX 1: Binary patches (winewayland.so) ==========
echo "=== Fix 1: winewayland.so binary patches ==="
if python3 "$SCRIPTS_DIR/apply_patch.py" 2>&1; then
    echo "  ✓ Binary patches applied/verified"
else
    echo "  ! Patch check failed (non-fatal, continuing)"
fi

# ========== FIX 2: AppInit DLL (CEF child→popup) ==========
echo "=== Fix 2: fix_createwindow.dll (CEF import dialog) ==="
HOOK_DLL="fix_createwindow.dll"
if [ ! -f "$PATCH_SOURCE" ]; then
    echo "WARNING: fix_createwindow source not found at $PATCH_SOURCE (AppInit will be skipped)"
fi
if command -v x86_64-w64-mingw32-gcc &>/dev/null && [ -f "$PATCH_SOURCE" ]; then
    x86_64-w64-mingw32-gcc -shared -O2 -s -o /tmp/fix_createwindow.dll "$PATCH_SOURCE" 2>/dev/null || true
fi
mkdir -p "$WINEPREFIX/drive_c/windows/system32" 2>/dev/null
if [ -f /tmp/fix_createwindow.dll ]; then
    cp /tmp/fix_createwindow.dll "$WINEPREFIX/drive_c/windows/system32/$HOOK_DLL" 2>/dev/null
    "$PROTON_DIR/files/bin/wine64" reg add "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Windows" /v "AppInit_DLLs" /t REG_SZ /d "C:\\windows\\system32\\$HOOK_DLL" /f 2>/dev/null
    "$PROTON_DIR/files/bin/wine64" reg add "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Windows" /v "LoadAppInit_DLLs" /t REG_DWORD /d 1 /f 2>/dev/null
    echo "  ✓ AppInit DLL registered"
fi

# ========== FIX 3: GPU Fix (Pref Patching) ==========
echo "=== Fix 3: GPU pref patching (CameraRaw startup probe workaround) ==="
python3 "$SCRIPTS_DIR/gpu_pref_patcher.py" off
echo "  ✓ GPU set to OFF in preferences (toggle ON in Lightroom for acceleration)"

# ========== ENVIRONMENT ==========
export PROTON_ENABLE_WAYLAND=1
export PROTON_WAYLAND_MONITOR="$MONITOR"
export GBM_BACKEND=nvidia-drm
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export DXVK_CONFIG_FILE="$DXVK_CONF"
export CHROMIUM_FLAGS="--in-process-gpu"
export WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS="$CHROMIUM_FLAGS"
export WINEDLLOVERRIDES="d2d1=n,b;Microsoft.AI.MachineLearning=n,b"
export PROTON_LOG=1
export PROTON_LOG_DIR="$LOG_DIR"

# ========== LAUNCH ==========
echo "=== Launching Lightroom ==="
STEAM_COMPAT_DATA_PATH="$STEAM_COMPAT_DATA_PATH" \
STEAM_COMPAT_CLIENT_INSTALL_PATH="$STEAM_COMPAT_CLIENT_INSTALL_PATH" \
WINEPREFIX="$WINEPREFIX" \
DXVK_CONFIG_FILE="$DXVK_CONFIG_FILE" \
PROTON_LOG="$PROTON_LOG" \
PROTON_LOG_DIR="$PROTON_LOG_DIR" \
PROTON_ENABLE_WAYLAND="$PROTON_ENABLE_WAYLAND" \
PROTON_WAYLAND_MONITOR="$PROTON_WAYLAND_MONITOR" \
GBM_BACKEND="$GBM_BACKEND" \
__GLX_VENDOR_LIBRARY_NAME="$__GLX_VENDOR_LIBRARY_NAME" \
CHROMIUM_FLAGS="$CHROMIUM_FLAGS" \
WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS="$WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS" \
WINEDLLOVERRIDES="$WINEDLLOVERRIDES" \
WINEDEBUG="$WINEDEBUG" \
"$PROTON_DIR/proton" run "$LR_EXE" 2>&1 | tee "$LOG_DIR/lr_wayland.log"

LR_EXIT=$?
echo "Lightroom exited with code $LR_EXIT"

# ========== CLEANUP ==========
echo "=== Cleanup ==="
# Remove AppInit registry entries
"$PROTON_DIR/files/bin/wine64" reg delete "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Windows" /v "AppInit_DLLs" /f 2>/dev/null
"$PROTON_DIR/files/bin/wine64" reg delete "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Windows" /v "LoadAppInit_DLLs" /f 2>/dev/null
echo "  ✓ AppInit registry cleaned"
echo "=== Done ==="
