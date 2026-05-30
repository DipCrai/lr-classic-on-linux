# Adobe Lightroom Classic on Linux

Fixes for running **Adobe Lightroom Classic** on Linux with **Wine/Proton**.

| Feature | Wayland | X11 |
|---------|---------|-----|
| Main window | ✅ Visible (patch required) | ❌ Unfixable flicker |
| CEF Import Dialog | ❌ Opens but **freezes** on folder select | ⚠️ Works (via X11 child windows) |
| Image Previews | ❓ Untested (binary patch may help) | ✅ Works |
| Histogram | ❌ Broken (D2D1 stub incomplete) | ❌ Broken (D2D1 stub incomplete) |
| Develop module | ❓ Untested (previews unconfirmed) | ⚠️ Works but flickers |

## Quick Start

```bash
# Clone repo
git clone https://github.com/DipCrai/lr-classic-on-linux.git
cd lr-classic-on-linux

# 1. Apply binary patch (required for Wayland)
python3 scripts/apply_patch.py

# 2. Set up prefix and install VC++ runtimes
WINEPREFIX=$HOME/.lightroom_prefix/pfx winetricks -q vcrun2022

# 3. Install CC stub DLLs (see GUIDE.md)
cp /path/to/stubs/*.dll "$WINEPREFIX/drive_c/windows/system32/"

# 4. Launch!
./scripts/launch_lightroom.sh
```

See [GUIDE.md](GUIDE.md) for full setup instructions and configuration.

## The Problem

`winewayland.drv` creates a `wl_subsurface` on the **same** `wl_surface` used by `VkSurfaceKHR`. Wayland forbids giving a surface multiple roles. The NVIDIA Wayland driver enforces this and refuses swapchain creation → gray previews and hangs.

**Fix**: A binary patch reorders operations so the subsurface is created **before** `vkCreateWaylandSurfaceKHR`, avoiding the role conflict.

## Two Display Modes

### Wayland (recommended)
- Flicker-free rendering
- Requires: binary patch + fix_createwindow.dll + dxvk.conf
- Launch: `scripts/launch_lightroom.sh`

### X11 (not recommended)
- Unfixable flicker on NVIDIA 580.159.03 (driver bug)
- No binary patch needed
- Launch: `scripts/launch_lightroom_x11.sh`

## Root Cause

Detailed analysis in [docs/ROOT_CAUSE.md](docs/ROOT_CAUSE.md). Brief call chain:

```
D3D11CreateDeviceAndSwapChain(child HWND)
 → DXVK → vkCreateWin32SurfaceKHR(hwnd)
 → winewayland.drv → wayland_vulkan_surface_create(hwnd)
   → wl_compositor_create_surface() → wl_surface
   → vkCreateWaylandSurfaceKHR(wl_surface)    ← VkSurface role
   → set_client_surface(hwnd, client)
     → wl_subcompositor.get_subsurface(wl_surface)  ← wl_subsurface role (CONFLICT!)
     → NVIDIA refuses swapchain → DXVK hangs
```

## What's in this repo

| Directory | Contents |
|-----------|----------|
| `scripts/` | Launchers, patch tools, build scripts |
| `patches/` | Source code for fix_createwindow.dll, LD_PRELOAD alternatives |
| `docs/` | Root cause analysis |
| `stubs/` | Download instructions for CC stub DLLs |

## Known Issues

- **Import freeze**: CEF dialog opens but **freezes on folder select** (main thread zombie)
- **Previews**: UNTESTED on Wayland — may still be gray/invisible
- **Histogram**: Broken (D2D1 rendering — patched stub is incomplete)
- **Scrolling**: Minor ghosting on Wayland
- **Fullscreen**: May misbehave with fix_createwindow (WS_POPUP windows)

See [KNOWN_ISSUES.md](KNOWN_ISSUES.md).

## AI Disclosure

This project was developed with assistance from an AI coding agent (opencode). The analysis, patches, and documentation were produced through iterative collaboration between human and AI.

## License

MIT
