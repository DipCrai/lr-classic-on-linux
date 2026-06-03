#!/bin/bash
# Lightroom Classic on Linux — X11 launcher (RECOMMENDED)
# X11 is the recommended mode: Import ✅, Previews ✅, Library histogram ✅, Develop histogram ✅.
# Develop live preview flickers on NVIDIA 580.159.03 — use Wayland for Develop.
# Source: https://github.com/DipCrai/lr-classic-on-linux
set -o pipefail

# ========== CONFIGURATION ==========
# NOTE: LR_DIR defaults to repo root, LR_EXE defaults to LR_DIR/Lightroom.exe.
# Override LR_DIR or LR_EXE if Lightroom.exe is elsewhere:
LR_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WINEPREFIX="${WINEPREFIX:-$HOME/.lightroom_prefix/pfx}"
STEAM_COMPAT_DATA_PATH="${STEAM_COMPAT_DATA_PATH:-$HOME/.lightroom_prefix}"
STEAM_COMPAT_CLIENT_INSTALL_PATH="${STEAM_COMPAT_CLIENT_INSTALL_PATH:-$HOME/.steam/root}"
PROTON_DIR="${PROTON_DIR:-$STEAM_COMPAT_CLIENT_INSTALL_PATH/compatibilitytools.d/Proton-GE Latest}"
LR_EXE="${LR_EXE:-$LR_DIR/Lightroom.exe}"
DXVK_CONF="${DXVK_CONF:-$LR_DIR/dxvk.conf}"
SCRIPTS_DIR="$(dirname "$0")"
LOG_DIR="${LOG_DIR:-/tmp/proton_logs}"

# Validate Lightroom executable exists
if [ ! -f "$LR_EXE" ]; then
    echo "ERROR: Lightroom executable not found at: $LR_EXE"
    echo "Set LR_EXE to your Lightroom.exe path, e.g.:"
    echo "  LR_EXE=/path/to/Lightroom.exe ./scripts/launch_lightroom_x11.sh"
    echo "  LR_DIR=/path/to/lightroom  ./scripts/launch_lightroom_x11.sh"
    exit 1
fi

# Warn if DXVK config not found
if [ ! -f "$DXVK_CONF" ]; then
    echo "WARNING: dxvk.conf not found at $DXVK_CONF"
fi

# ========== DISPLAY BACKEND: X11 ==========
unset PROTON_ENABLE_WAYLAND
unset PROTON_WAYLAND_MONITOR
unset GBM_BACKEND
export DISPLAY="${DISPLAY:-:0}"

if nvidia-smi &>/dev/null; then
    export __GLX_VENDOR_LIBRARY_NAME=nvidia
fi

# DXVK
export DXVK_CONFIG_FILE="$DXVK_CONF"

# CEF flags (same as Wayland — GPU compositing required for CEF to render)
export CHROMIUM_FLAGS="--in-process-gpu"
export WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS="$CHROMIUM_FLAGS"

# DLL overrides
export WINEDLLOVERRIDES="d2d1=n,b;Microsoft.AI.MachineLearning=n,b"

# ========== AppInit DLL: CEF child→popup conversion ==========
# X11 variant (strips frame styles) — use fix_createwindow.c for Wayland
HOOK_DLL="fix_createwindow.dll"
PATCH_SOURCE="${PATCH_SOURCE:-$LR_DIR/patches/fix_createwindow_x11.c}"
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
fi

# ========== GPU Fix: Pref Patching ==========
# Workaround: start with GPU=OFF in Lightroom preferences (avoids broken
# CameraRaw startup probe). User enables GPU in Preferences → CameraRaw
# re-initializes via the working probe path.
python3 "$SCRIPTS_DIR/gpu_pref_patcher.py" off
echo "[GPU] GPU set to OFF in preferences (toggle ON in Lightroom settings for full acceleration)"

# ========== GPU Fix: CameraRaw GPU Config Lock ==========
# CameraRaw's GPU probe is unreliable on Proton. By providing a known-good
# Camera Raw GPU Config.txt and locking it read-only, CameraRaw skips the
# probe and uses the cached working state — fixing all histograms.
CAMERA_RAW_GPU_DIR="$WINEPREFIX/drive_c/users/steamuser/AppData/Roaming/Adobe/CameraRaw/GPU/Adobe Photoshop Lightroom Classic"
CAMERA_RAW_GPU_CFG="$CAMERA_RAW_GPU_DIR/Camera Raw GPU Config.txt"
mkdir -p "$CAMERA_RAW_GPU_DIR"

if [ -f "$CAMERA_RAW_GPU_CFG" ] && grep -q 'crs:gpu_compute_quick_self_test_passed="True"' "$CAMERA_RAW_GPU_CFG" 2>/dev/null; then
    echo "[GPU] CameraRaw GPU config valid, locking read-only"
else
    echo "[GPU] Creating golden CameraRaw GPU config (probe workaround)"
    cat > "$CAMERA_RAW_GPU_CFG" << 'GOLDEN_EOF'
<x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Adobe XMP Core 7.0-c000 1.000000, 0000/00/00-00:00:00        ">
 <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
  <rdf:Description rdf:about=""
    xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
   crs:gpu_preferred_system=""
   crs:gpu_init_digest="742E562419B091D522C9DB42B370F46A"
   crs:gpu_compute_digest="3A58040472A0AB0D95057E860EDADD8D"
   crs:gpu_compute_quick_self_test_passed="True"
   crs:gpu_hdr_display_scale="1"
   crs:gpu_noise_fudge="0"
   crs:gpu_trimap_dilate_radius="0.01"
   crs:gpu_trimap_erode_radius="0.01"/>
 </rdf:RDF>
</x:xmpmeta>
GOLDEN_EOF
fi
chmod 444 "$CAMERA_RAW_GPU_CFG"
echo "[GPU] CameraRaw GPU config locked (read-only)"

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

# ========== Cleanup ==========
# Cleanup AppInit
"$PROTON_DIR/files/bin/wine64" reg delete "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Windows" /v "AppInit_DLLs" /f 2>/dev/null
"$PROTON_DIR/files/bin/wine64" reg delete "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Windows" /v "LoadAppInit_DLLs" /f 2>/dev/null
# Restore CameraRaw GPU config writability (for future updates)
chmod 644 "$CAMERA_RAW_GPU_CFG" 2>/dev/null

