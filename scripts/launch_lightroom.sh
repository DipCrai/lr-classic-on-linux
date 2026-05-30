#!/bin/bash
set -o pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WINEPREFIX="/tmp/lightroom_steam_compat/pfx"
STEAM_COMPAT_DATA_PATH="/tmp/lightroom_steam_compat"
STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.steam/root"
PROTON_DIR="$STEAM_COMPAT_CLIENT_INSTALL_PATH/compatibilitytools.d/Proton-GE Latest"
export WINEPREFIX

# === Wayland ===
export PROTON_ENABLE_WAYLAND=1
export PROTON_WAYLAND_MONITOR=HDMI-A-1

# === NVIDIA GBM ===
export GBM_BACKEND=nvidia-drm
export __GLX_VENDOR_LIBRARY_NAME=nvidia

# === DXVK ===
export DXVK_CONFIG_FILE="$SCRIPT_DIR/dxvk.conf"

# === CEF ===
export CHROMIUM_FLAGS="--in-process-gpu"
export WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS="$CHROMIUM_FLAGS"

# === LD_PRELOAD: block wl_subsurface for VkSurface surfaces ===
# winewayland.drv creates wl_subsurface on the SAME wl_surface used for VkSurfaceKHR.
# NVIDIA Wayland driver rejects VkSurface on surfaces with wl_subsurface role.
# This LD_PRELOAD:
# 1. Intercepts vkCreateWaylandSurfaceKHR → tracks which wl_surfaces have VkSurface
# 2. Intercepts wl_subcompositor.get_subsurface → blocks if child has VkSurface
# 3. Keeps D3D surfaces role-less → VkSurface/NVIDIA OK
# 4. GDI surfaces continue to get subsurfaces normally
export LD_PRELOAD="/home/ivan/lrcfix/libwl_got_patch.so${LD_PRELOAD:+:$LD_PRELOAD}"

# === AppInit DLL (fix_createwindow — CEF child→popup conversion) ===
HOOK_DLL="fix_createwindow.dll"
if command -v x86_64-w64-mingw32-gcc &>/dev/null && [ -f /home/ivan/lrcfix/fix_createwindow.c ]; then
    x86_64-w64-mingw32-gcc -shared -O2 -s -o /tmp/fix_createwindow.dll /home/ivan/lrcfix/fix_createwindow.c 2>/tmp/gcc_dll.log || true
fi
"$PROTON_DIR/files/bin/wine64" wineboot -u 2>/dev/null || true
if [ -f /tmp/fix_createwindow.dll ]; then
    mkdir -p "$WINEPREFIX/drive_c/windows/system32" 2>/dev/null
    cp /tmp/fix_createwindow.dll "$WINEPREFIX/drive_c/windows/system32/$HOOK_DLL" 2>/dev/null
    "$PROTON_DIR/files/bin/wine64" reg add "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Windows" /v "AppInit_DLLs" /t REG_SZ /d "C:\\windows\\system32\\$HOOK_DLL" /f 2>/dev/null
    "$PROTON_DIR/files/bin/wine64" reg add "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Windows" /v "LoadAppInit_DLLs" /t REG_DWORD /d 1 /f 2>/dev/null
fi

# === DLL overrides ===
export WINEDLLOVERRIDES="d2d1=n,b;Microsoft.AI.MachineLearning=n,b"

# === Логи ===
export PROTON_LOG=1
export PROTON_LOG_DIR=/tmp/proton_logs
mkdir -p /tmp/proton_logs

# === Запуск ===
STEAM_COMPAT_DATA_PATH="$STEAM_COMPAT_DATA_PATH" \
STEAM_COMPAT_CLIENT_INSTALL_PATH="$STEAM_COMPAT_CLIENT_INSTALL_PATH" \
WINEPREFIX="$WINEPREFIX" \
DXVK_CONFIG_FILE="$DXVK_CONFIG_FILE" \
PROTON_LOG="$PROTON_LOG" \
PROTON_LOG_DIR="$PROTON_LOG_DIR" \
PROTON_ENABLE_WAYLAND="$PROTON_ENABLE_WAYLAND" \
GBM_BACKEND="$GBM_BACKEND" \
__GLX_VENDOR_LIBRARY_NAME="$__GLX_VENDOR_LIBRARY_NAME" \
CHROMIUM_FLAGS="$CHROMIUM_FLAGS" \
WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS="$WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS" \
WINEDLLOVERRIDES="$WINEDLLOVERRIDES" \
LD_PRELOAD="$LD_PRELOAD" \
"$PROTON_DIR/proton" runinprefix "$SCRIPT_DIR/Lightroom.exe" 2>&1 | tee /tmp/lr_wayland.log

echo "Exit: $?"

# === Чистим AppInit ===
"$PROTON_DIR/files/bin/wine64" reg delete "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Windows" /v "AppInit_DLLs" /f 2>/dev/null
"$PROTON_DIR/files/bin/wine64" reg delete "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Windows" /v "LoadAppInit_DLLs" /f 2>/dev/null
