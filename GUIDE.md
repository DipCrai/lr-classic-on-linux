# Setup Guide

## Requirements

- Fedora 44+ (or any distro with recent GNOME/Wayland)
- NVIDIA GPU with driver 570+ (tested on 580.159.03)
- GE-Proton10-34+
- Lightroom Classic 13.x

## 1. Install GE-Proton

```bash
# Download GE-Proton
wget https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton10-34/GE-Proton10-34.tar.gz
mkdir -p ~/.steam/root/compatibilitytools.d/
tar -xzf GE-Proton10-34.tar.gz -C ~/.steam/root/compatibilitytools.d/
```

## 2. Create Wine Prefix

```bash
export WINEPREFIX=/tmp/lightroom_steam_compat/pfx
export STEAM_COMPAT_DATA_PATH=/tmp/lightroom_steam_compat
export STEAM_COMPAT_CLIENT_INSTALL_PATH=$HOME/.steam/root
PROTON="$HOME/.steam/root/compatibilitytools.d/Proton-GE Latest/proton"

# Create prefix
"$PROTON" wineboot -u
```

## 3. Install Lightroom

Install Lightroom Classic via the official installer. Use the Proton prefix:

```bash
"$PROTON" run "/path/to/Lightroom_Classic_xxxx_Setup.exe"
```

## 4. Apply CC Stubs

Copy the stub DLLs from [patchforCC/lightroom-cc-on-linux-main/stubs/binaries/](https://github.com/dipcrai/lr-classic-on-linux/tree/main/stubs)
to the prefix:

```bash
cp stubs/*.dll "$WINEPREFIX/drive_c/windows/system32/"
cp stubs/*.dll "/path/to/lightroom/dir/"
```

These fix:
- `d2d1.dll` — missing CLSID_D2D1ColorManagement (crash on startup)
- `mfplat.dll` — Media Foundation stubs (tutorial/Remove/Heal crash)
- `adobe_e26b366d.dll` — Adobe CLSID probe
- `thumbcache.dll` — Local thumbnail cache stub
- `hnetcfg.dll` — Firewall rules stub

## 5. Apply winewayland.drv Binary Patch

```bash
python3 scripts/apply_patch.py
```

This patches `winewayland.so` to create sub surfaces before VkSurface.

## 6. Build & Install fix_createwindow.dll

```bash
x86_64-w64-mingw32-gcc -shared -O2 -s -o fix_createwindow.dll patches/fix_createwindow.c
cp fix_createwindow.dll "$WINEPREFIX/drive_c/windows/system32/"

# Register as AppInit DLL
"$PROTON/files/bin/wine64" reg add "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Windows" /v "AppInit_DLLs" /t REG_SZ /d "C:\\windows\\system32\\fix_createwindow.dll" /f
"$PROTON/files/bin/wine64" reg add "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Windows" /v "LoadAppInit_DLLs" /t REG_DWORD /d 1 /f
```

## 7. Create dxvk.conf

Place in Lightroom directory:

```ini
dxgi.deferSurfaceCreation = True
d3d11.enableDiscard = False
d3d11.maxFeatureLevel = 11_0
dxgi.maxFrameLatency = 1
dxgi.numBackBuffers = 3
dxgi.syncInterval = 0
```

## 8. Launch

```bash
./scripts/launch_lightroom.sh
```

Or set environment variables manually:

```bash
export WINEPREFIX=/tmp/lightroom_steam_compat/pfx
export STEAM_COMPAT_DATA_PATH=/tmp/lightroom_steam_compat
export STEAM_COMPAT_CLIENT_INSTALL_PATH=$HOME/.steam/root
export DXVK_CONFIG_FILE=/path/to/dxvk.conf
export PROTON_ENABLE_WAYLAND=1
export PROTON_WAYLAND_MONITOR=HDMI-A-1
export GBM_BACKEND=nvidia-drm
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export CHROMIUM_FLAGS="--in-process-gpu"
export WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS="--in-process-gpu"
export WINEDLLOVERRIDES="d2d1=n,b;Microsoft.AI.MachineLearning=n,b"

"$HOME/.steam/root/compatibilitytools.d/Proton-GE Latest/proton" run /path/to/Lightroom.exe
```
