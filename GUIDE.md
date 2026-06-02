# Setup Guide

## Requirements

- **GE-Proton10-34+** — [GE-Proton releases](https://github.com/GloriousEggroll/proton-ge-custom/releases)
- **Lightroom Classic 13.x** (installed via official Adobe installer)
- **mingw-w64-gcc** — for building `fix_createwindow.dll`:
  ```bash
  sudo dnf install mingw64-gcc        # Fedora
  sudo apt install mingw-w64          # Debian/Ubuntu
  ```

## Tested On

| Environment | Config |
|-------------|--------|
| Distro | Fedora 44, Arch Linux |
| Desktop | GNOME (Wayland), Hyprland + Caelestia |
| GPU | NVIDIA GTX 1080 Ti (Pascal) |
| Driver | NVIDIA 580.159.03 (likely works on AMD too) |

## Quick Start

```bash
# 1. Clone
git clone https://github.com/DipCrai/lr-classic-on-linux.git
cd lr-classic-on-linux

# 2. Apply winewayland binary patch (required for Wayland only)
./scripts/apply_patch.py

# 3. Download and install CC stub DLLs
./scripts/download-stubs.sh
cp stubs/*.dll "$WINEPREFIX/drive_c/windows/system32/"
cp stubs/*.dll "/path/to/lightroom/"

# 4. Launch!
./scripts/launch_lightroom_x11.sh   # X11 — stable, recommended
./scripts/launch_lightroom.sh       # Wayland — flicker-free Develop, partial otherwise
```

## Step-by-Step

### 1. Install GE-Proton

```bash
wget https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton10-34/GE-Proton10-34.tar.gz
mkdir -p ~/.steam/root/compatibilitytools.d/
tar -xzf GE-Proton10-34.tar.gz -C ~/.steam/root/compatibilitytools.d/
```

### 2. Install Lightroom

```bash
export WINEPREFIX=$HOME/.lightroom_prefix/pfx
export STEAM_COMPAT_DATA_PATH=$HOME/.lightroom_prefix
export STEAM_COMPAT_CLIENT_INSTALL_PATH=$HOME/.steam/root
PROTON="$HOME/.steam/root/compatibilitytools.d/Proton-GE Latest/proton"
"$PROTON" wineboot -u
"$PROTON" run "/path/to/Lightroom_Classic_Setup.exe"
```

### 3. Install VC++ Runtimes

```bash
WINEPREFIX=$HOME/.lightroom_prefix/pfx winetricks -q vcrun2022
```

### 4. Copy CC Stub DLLs

Get from [sander110419/lightroom-cc-on-linux](https://github.com/sander110419/lightroom-cc-on-linux/tree/main/stubs/binaries) or use `./scripts/download-stubs.sh`:

| DLL | Purpose |
|-----|---------|
| `d2d1.dll` | Missing CLSID_D2D1ColorManagement (crash on startup) |
| `mfplat.dll` | Media Foundation stubs (tutorial/Remove/Heal crash) |
| `adobe_e26b366d.dll` | Adobe CLSID probe → S_FALSE |
| `thumbcache.dll` | Local thumbnail cache stub |
| `hnetcfg.dll` | Firewall rules stub |

```bash
./scripts/download-stubs.sh
cp stubs/*.dll "$WINEPREFIX/drive_c/windows/system32/"
cp stubs/*.dll "/path/to/lightroom/"
```

**Important**: `d2d1.dll` must be overridden as native, set in `WINEDLLOVERRIDES`:
```
WINEDLLOVERRIDES="d2d1=n,b;Microsoft.AI.MachineLearning=n,b"
```

### 5. Apply winewayland.drv Binary Patch (Wayland only)

Required for Wayland mode. Patches winewayland.so to avoid `wl_surface` role conflict:

```bash
python3 scripts/apply_patch.py
```

**Build-specific**: GE-Proton10-34 only. When updating Proton:
1. Revert: `bash scripts/revert_patch.sh`
2. Install new Proton
3. Update offsets in `scripts/apply_patch.py`

### 6. Build & Install fix_createwindow.dll

Converts CEF child windows to popup windows (required for Wayland import dialog):

```bash
x86_64-w64-mingw32-gcc -shared -O2 -s -o /tmp/fix_createwindow.dll patches/fix_createwindow.c
cp /tmp/fix_createwindow.dll "$WINEPREFIX/drive_c/windows/system32/"
```

The launcher scripts handle AppInit registration automatically.

### 7. Create dxvk.conf

Place in Lightroom directory or set `DXVK_CONF`:

```ini
dxgi.deferSurfaceCreation = True
d3d11.enableDiscard = False
d3d11.maxFeatureLevel = 11_0
dxgi.maxFrameLatency = 1
dxgi.numBackBuffers = 3
dxgi.syncInterval = 0
```

- `maxFeatureLevel = 11_0` — **required** (10_0 causes white import window)
- `syncInterval = 0` — prevents stuttering

### 8. Launch

#### X11 (recommended — stable)

```bash
./scripts/launch_lightroom_x11.sh
```

Features: Import ✅, Previews ✅, Library histogram ✅, Develop histogram ✅, Develop ⚠️ (flickers only — no other issues on X11).

**GPU Pref Trick enabled by default**: The launcher runs `gpu_pref_patcher.py off` before starting Lightroom. This sets `GPUManagerPref = "off"` in Lightroom preferences, causing CameraRaw to skip its broken startup GPU probe. After Lightroom is fully loaded, go to **Preferences → Performance** and enable GPU acceleration — CameraRaw re-initializes via a working code path.

#### Wayland (flicker-free Develop)

```bash
./scripts/launch_lightroom.sh
```

Features: Main window ✅, Develop ✅ (no flicker), Library histogram ✅, Develop histogram ✅, Import ❌ (freeze), Previews ❌ (gray).

#### Configuration Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `WINEPREFIX` | `~/.lightroom_prefix/pfx` | Wine prefix |
| `PROTON_DIR` | `~/.steam/root/.../Proton-GE Latest` | Proton installation |
| `LR_EXE` | `<repo_parent>/Lightroom.exe` | Lightroom executable |
| `MONITOR` | `HDMI-A-1` | Wayland monitor name |
| `DXVK_CONF` | `<LR_DIR>/dxvk.conf` | DXVK config path |
| `LOG_DIR` | `/tmp/proton_logs` | Log output directory |

### 9. GPU Pref Trick (CameraRaw Startup Probe)

Lightroom's CameraRaw module does a GPU probe at startup using a code path that fails on Wine/Proton. This causes import freezes, gray previews, and broken histogram.

**Workaround**: Launch Lightroom with GPU disabled in preferences, then enable it after startup:

```bash
# Before launch: set GPU to OFF
python3 scripts/gpu_pref_patcher.py off

# Launch Lightroom
./scripts/launch_lightroom_x11.sh

# After Lightroom is fully loaded: go to Preferences → Performance → enable GPU
```

The launcher scripts handle the `gpu_pref_patcher.py off` call automatically. After Lightroom starts, toggle GPU ON in Preferences → Performance.

The patcher modifies `Lightroom Classic CC 7 Preferences.agprefs` in the Wine prefix:
```
WINEPREFIX/drive_c/users/steamuser/AppData/Roaming/Adobe/Lightroom/Preferences/
```

Key preference changed: `GPUManagerPref = "off"` → skip CameraRaw GPU probe at startup.

### 10. Develop Histogram

The Develop histogram was previously thought to be a DXVK/vkd3d-proton conflict on Pascal GPUs. This was incorrect — it was CameraRaw's failed GPU probe corrupting compute state. With the GPU pref trick (`GPUManagerPref = "off"` at launch, toggle ON after startup), CameraRaw initializes cleanly and the Develop histogram works on X11.

**Wayland**: Develop histogram works with the GPU pref trick (same as X11). Library histogram also works. Import ❌ and previews ❌ are the only remaining Wayland issues.

## Troubleshooting

### "mfc140u.dll not found"

```bash
WINEPREFIX=$HOME/.lightroom_prefix/pfx winetricks -q vcrun2022
```

### Lightroom exits immediately (exit code 53)

Run with `WINEDEBUG=+loaddll` to find missing DLL.

### "ProtonFixes: Skipping fix execution"

Set `SteamAppId=480` or run via Steam. Cosmetic.

### Import dialog white/frozen

1. Check `CHROMIUM_FLAGS` — `--in-process-gpu`, NOT `--disable-gpu`
2. Check `fix_createwindow.dll` registered in AppInit_DLLs
3. Check `d3d11.maxFeatureLevel = 11_0` in dxvk.conf
4. X11 import works ✅; Wayland import freezes on folder select ❌

### Flickering on X11

Switch to Wayland for Develop module work. This is a known NVIDIA driver bug.

### Develop histogram blank

On X11: Make sure you toggled GPU ON in Preferences → Performance after launching. The launcher starts Lightroom with GPU=OFF; you must enable it in the UI.

On Wayland: Develop histogram is broken due to wl_surface role conflict (no GPU compute on Wayland via DXVK).

## Files

| File | Purpose |
|------|---------|
| `scripts/launch_lightroom.sh` | Wayland launcher |
| `scripts/launch_lightroom_x11.sh` | X11 launcher (recommended) |
| `scripts/apply_patch.py` | Binary patch for winewayland.so |
| `scripts/revert_patch.sh` | Revert binary patch |
| `scripts/download-stubs.sh` | Download CC stub DLLs |
| `patches/fix_createwindow.c` | CEF child→popup conversion DLL |
| `patches/wine/0001-*.patch` | Wine d3d11 CreateDirect3D11DeviceFromDXGIDevice |
| `patches/wine/0002-*.patch` | Wine winewayland subsurface reorder |
| `dxvk.conf` | DXVK configuration |
| `docs/ROOT_CAUSE.md` | Root cause analysis |
| `AGENTS.md` | AI session knowledge base |
