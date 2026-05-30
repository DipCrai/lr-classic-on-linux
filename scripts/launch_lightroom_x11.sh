#!/bin/bash
# Lightroom Classic on Linux — X11 launcher
# NOTE: X11 has UNFIXABLE flickering on NVIDIA 580.159.03 driver.
# This is provided for reference only — use Wayland (launch_lightroom.sh) for a working setup.
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
LOG_DIR="${LOG_DIR:-/tmp/proton_logs}"

# ========== DISPLAY BACKEND: X11 ==========
unset PROTON_ENABLE_WAYLAND
unset PROTON_WAYLAND_MONITOR
unset GBM_BACKEND
export DISPLAY="${DISPLAY:-:0}"

# NVIDIA
export __GLX_VENDOR_LIBRARY_NAME=nvidia

# DXVK
export DXVK_CONFIG_FILE="$DXVK_CONF"

# CEF flags (disable GPU compositing on X11 to reduce flicker)
export CHROMIUM_FLAGS="--disable-gpu --in-process-gpu"
export WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS="$CHROMIUM_FLAGS"

# DLL overrides
export WINEDLLOVERRIDES="d2d1=n,b;Microsoft.AI.MachineLearning=n,b"

# ========== AppInit DLL: CEF child→popup conversion ==========
HOOK_DLL="fix_createwindow.dll"
PATCH_SOURCE="${PATCH_SOURCE:-$LR_DIR/patches/fix_createwindow.c}"
if command -v x86_64-w64-mingw32-gcc &>/dev/null && [ -f "$PATCH_SOURCE" ]; then
    x86_64-w64-mingw32-gcc -shared -O2 -s -o /tmp/fix_createwindow.dll "$PATCH_SOURCE" 2>/dev/null || true
fi
mkdir -p "$WINEPREFIX/drive_c/windows/system32" 2>/dev/null
if [ -f /tmp/fix_createwindow.dll ]; then
    cp /tmp/fix_createwindow.dll "$WINEPREFIX/drive_c/windows/system32/$HOOK_DLL" 2>/dev/null
    "$PROTON_DIR/files/bin/wine64" reg add "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Windows" /v "AppInit_DLLs" /t REG_SZ /d "C:\\windows\\system32\\$HOOK_DLL" /f 2>/dev/null
    "$PROTON_DIR/files/bin/wine64" reg add "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Windows" /v "LoadAppInit_DLLs" /t REG_DWORD /d 1 /f 2>/dev/null
fi

# ========== Logs ==========
export PROTON_LOG=1
export PROTON_LOG_DIR="$LOG_DIR"
mkdir -p "$LOG_DIR"

# ========== Launch ==========
STEAM_COMPAT_DATA_PATH="$STEAM_COMPAT_DATA_PATH" \
STEAM_COMPAT_CLIENT_INSTALL_PATH="$STEAM_COMPAT_CLIENT_INSTALL_PATH" \
WINEPREFIX="$WINEPREFIX" \
DXVK_CONFIG_FILE="$DXVK_CONFIG_FILE" \
PROTON_LOG="$PROTON_LOG" \
PROTON_LOG_DIR="$PROTON_LOG_DIR" \
__GLX_VENDOR_LIBRARY_NAME="$__GLX_VENDOR_LIBRARY_NAME" \
DISPLAY="$DISPLAY" \
CHROMIUM_FLAGS="$CHROMIUM_FLAGS" \
WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS="$WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS" \
WINEDLLOVERRIDES="$WINEDLLOVERRIDES" \
"$PROTON_DIR/proton" run "$LR_EXE" 2>&1 | tee "$LOG_DIR/lr_x11.log"

echo "Exit: $?"

# ========== Cleanup AppInit ==========
"$PROTON_DIR/files/bin/wine64" reg delete "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Windows" /v "AppInit_DLLs" /f 2>/dev/null
"$PROTON_DIR/files/bin/wine64" reg delete "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Windows" /v "LoadAppInit_DLLs" /f 2>/dev/null
