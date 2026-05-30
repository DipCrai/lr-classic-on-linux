# Setup Guide

## Requirements

- **Fedora 44+** (or any distro with recent GNOME/Wayland)
- **NVIDIA GPU** with driver 570+ (tested on 580.159.03)
- **GE-Proton10-34+** — download from [GE-Proton releases](https://github.com/GloriousEggroll/proton-ge-custom/releases)
- **Lightroom Classic 13.x** (installed via official Adobe installer)
- **mingw-w64-gcc** — for building `fix_createwindow.dll`:
  ```bash
  sudo dnf install mingw64-gcc        # Fedora
  sudo apt install mingw-w64          # Debian/Ubuntu
  ```

## Quick Start

```bash
# 1. Clone this repo
git clone https://github.com/DipCrai/lr-classic-on-linux.git
cd lr-classic-on-linux

# 2. Apply the winewayland.drv binary patch (required for Wayland)
./scripts/apply_patch.py

# 3. Copy the CC stub DLLs into the Lightroom directory and prefix
# (Download from the original patchforCC repo or use your existing stubs)
cp stubs/*.dll "/path/to/lightroom/"
cp stubs/*.dll "$WINEPREFIX/drive_c/windows/system32/"

# 4. Launch!
./scripts/launch_lightroom.sh
```

## Step-by-Step

### 1. Install GE-Proton

```bash
# Download GE-Proton
wget https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton10-34/GE-Proton10-34.tar.gz
mkdir -p ~/.steam/root/compatibilitytools.d/
tar -xzf GE-Proton10-34.tar.gz -C ~/.steam/root/compatibilitytools.d/
```

### 2. Install Lightroom

Use the official Lightroom Classic installer with the Proton prefix:

```bash
export WINEPREFIX=$HOME/.lightroom_prefix/pfx
export STEAM_COMPAT_DATA_PATH=$HOME/.lightroom_prefix
export STEAM_COMPAT_CLIENT_INSTALL_PATH=$HOME/.steam/root
PROTON="$HOME/.steam/root/compatibilitytools.d/Proton-GE Latest/proton"

# Create prefix
"$PROTON" wineboot -u

# Run installer (adjust path to your installer)
"$PROTON" run "/path/to/Lightroom_Classic_xxxx_Setup.exe"
```

### 3. Install VC++ Runtimes

Lightroom requires `mfc140u.dll` (Visual C++ 2015-2022). Install via winetricks:

```bash
WINEPREFIX=$HOME/.lightroom_prefix/pfx \
WINE="$PROTON/files/bin/wine64" \
WINELOADER="$PROTON/files/bin/wine64" \
WINESERVER="$PROTON/files/bin/wineserver" \
/path/to/protonfixes/winetricks -q vcrun2022
```

Or run Lightroom once — if it fails with "mfc140u.dll not found", install it with the command above.

### 4. Copy CC Stub DLLs

The stub DLLs fix several crashes and missing CLSID errors. Get them from the original [patchforCC/lightroom-cc-on-linux](https://github.com/dipcrai/lr-classic-on-linux/tree/main/stubs) repo, or use your existing ones:

| DLL | Purpose |
|-----|---------|
| `d2d1.dll` | Missing CLSID_D2D1ColorManagement (crash on startup) |
| `mfplat.dll` | Media Foundation stubs (tutorial/Remove/Heal crash) |
| `adobe_e26b366d.dll` | Adobe CLSID probe → S_FALSE |
| `thumbcache.dll` | Local thumbnail cache stub |
| `hnetcfg.dll` | Firewall rules stub |

```bash
cp stubs/*.dll "$WINEPREFIX/drive_c/windows/system32/"
cp stubs/*.dll "/path/to/lightroom/dir/"
```

**Important**: `d2d1.dll` MUST be overridden as native:
```
WINEDLLOVERRIDES="d2d1=n,b;Microsoft.AI.MachineLearning=n,b"
```

### 5. Apply winewayland.drv Binary Patch

This patch is **required** for Wayland mode. It reorders subsurface creation to avoid a `wl_surface` role conflict that NVIDIA's Wayland driver rejects:

```bash
python3 scripts/apply_patch.py
```

To revert (e.g., when updating Proton):
```bash
bash scripts/revert_patch.sh
```

### 6. Build & Install fix_createwindow.dll

This DLL converts CEF child windows to popup windows so they render correctly on Wayland:

```bash
# Build
x86_64-w64-mingw32-gcc -shared -O2 -s -o /tmp/fix_createwindow.dll patches/fix_createwindow.c

# Install to prefix
cp /tmp/fix_createwindow.dll "$WINEPREFIX/drive_c/windows/system32/"

# Register as AppInit DLL
"$PROTON/files/bin/wine64" reg add "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Windows" /v "AppInit_DLLs" /t REG_SZ /d "C:\\windows\\system32\\fix_createwindow.dll" /f
"$PROTON/files/bin/wine64" reg add "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Windows" /v "LoadAppInit_DLLs" /t REG_DWORD /d 1 /f
```

Or use the helper script: `bash scripts/build-fix_createwindow.sh`

### 7. Create dxvk.conf

Place this in your Lightroom directory:

```ini
dxgi.deferSurfaceCreation = True
d3d11.enableDiscard = False
d3d11.maxFeatureLevel = 11_0
dxgi.maxFrameLatency = 1
dxgi.numBackBuffers = 3
dxgi.syncInterval = 0
```

- `maxFeatureLevel = 11_0` is **required** (10_0 causes a white import window)
- `syncInterval = 0` prevents stuttering

### 8. Launch

#### Wayland (recommended — flicker-free)

```bash
./scripts/launch_lightroom.sh
```

This script auto-detects your Lightroom directory if run from the repo root. You can override defaults via environment variables:

```bash
LR_DIR=/path/to/lightroom WINEPREFIX=~/.custom_prefix/pfx MONITOR=DP-1 ./scripts/launch_lightroom.sh
```

| Variable | Default | Description |
|----------|---------|-------------|
| `WINEPREFIX` | `~/.lightroom_prefix/pfx` | Wine prefix location |
| `PROTON_DIR` | `~/.steam/root/compatibilitytools.d/Proton-GE Latest` | Proton installation |
| `LR_EXE` | `<repo_parent>/Lightroom.exe` | Lightroom executable |
| `MONITOR` | `HDMI-A-1` | Wayland monitor name |
| `DXVK_CONF` | `<LR_DIR>/dxvk.conf` | DXVK config path |

#### X11 (NOT recommended — unfixable flicker on NVIDIA 580+)

```bash
./scripts/launch_lightroom_x11.sh
```

X11 has persistent screen-tearing on NVIDIA driver 580.159.03 because the driver bypasses both Vulkan and GLX present modes. This is a **driver bug** with no known fix. Use Wayland instead.

### 9. Post-Launch Checks

After Lightroom starts:

1. **Import dialog**: Should open and show thumbnails. If white/frozen, ensure `--in-process-gpu` is set (NOT `--disable-gpu`) and `fix_createwindow.dll` is registered.
2. **Previews**: Should render correctly with the binary patch applied.
3. **Histogram**: Known broken (D2D1 rendering — patched stub doesn't implement all effects).
4. **Develop module**: Should work for most operations.

## Troubleshooting

### "mfc140u.dll not found"

VC++ runtime not installed. Run winetricks to install:
```bash
WINEPREFIX=$HOME/.lightroom_prefix/pfx winetricks -q vcrun2022
```

### Lightroom exits immediately (exit code 53)

DLL not found error. Run with `WINEDEBUG=+loaddll` to see which DLL is missing, then install the appropriate runtime.

### "ProtonFixes: Skipping fix execution"

Set `SteamAppId=480` or run via Steam. This is cosmetic — Lightroom should still work.

### Import dialog is white/frozen

1. Check `CHROMIUM_FLAGS` — must have `--in-process-gpu`, must NOT have `--disable-gpu`
2. Check `fix_createwindow.dll` is registered in AppInit_DLLs
3. Check `d3d11.maxFeatureLevel = 11_0` in dxvk.conf
4. Rebuild fix_createwindow.dll from `patches/fix_createwindow.c`

### Flickering on X11

Switch to Wayland. This is a known NVIDIA driver bug with no fix.

## Files

| File | Purpose |
|------|---------|
| `scripts/launch_lightroom.sh` | Wayland launcher (daily driver) |
| `scripts/launch_lightroom_x11.sh` | X11 launcher (reference only) |
| `scripts/apply_patch.py` | Binary patch for winewayland.so |
| `scripts/revert_patch.sh` | Revert the binary patch |
| `scripts/build-fix_createwindow.sh` | Build fix_createwindow.dll |
| `patches/fix_createwindow.c` | Source for CEF child→popup conversion |
| `patches/libwl_got_patch.c` | LD_PRELOAD alternative (for reference) |
| `patches/README.md` | Patch documentation |
| `dxvk.conf` | DXVK configuration |
| `docs/ROOT_CAUSE.md` | Root cause analysis |
