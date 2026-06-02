# Adobe Lightroom Classic on Wine/Proton — Full Report

**TL;DR**: Four issues block Lightroom on Linux:
1. **wl_surface role conflict** (VkSurface + wl_subsurface) → gray previews on Wayland
2. **CEF child windows** → white/frozen import dialog on Wayland
3. **X11 flickering** → NVIDIA 580.159.03 bypasses vsync on X11
4. **CameraRaw GPU probe fails at startup** → corrupts GPU compute state (Develop histogram, Library histogram, previews)

**Current recommendation**: Use **X11** with the **GPU pref trick** (start with GPU=OFF, toggle ON after launch). Everything works — import ✅, previews ✅, all histograms ✅. Only Develop module flickers slightly on X11. Use Wayland for flicker-free Develop work.

---

## Issue 1: wl_surface role conflict (CRITICAL — Wayland)

### Root Cause
`winewayland.drv` creates a `wl_subsurface` on the **same** `wl_surface` already used for `VkSurfaceKHR`. Wayland forbids assigning multiple roles. NVIDIA driver enforces this strictly (unlike Mesa which silently allows it).

### Call Chain
```
D3D11CreateDeviceAndSwapChain(hwnd=CHILD)
 → DXVK → vkCreateWin32SurfaceKHR(hwnd)
 → winewayland.drv → wayland_vulkan_surface_create(hwnd)
   → wl_compositor_create_surface() → wl_surface_A
   → vkCreateWaylandSurfaceKHR(..., wl_surface_A)  ← VkSurface role
   → set_client_surface(hwnd, client)
     → wl_subcompositor.get_subsurface(..., wl_surface_A)  ← wl_subsurface CONFLICT
     → NVIDIA refuses swapchain → DXVK hangs
```

### Fix
**Binary patch** (applied to GE-Proton10-34 `winewayland.so`): reorder `set_client_surface` BEFORE `vkCreateWaylandSurfaceKHR`. The wl_surface gets subsurface role first, then VkSurface — NVIDIA accepts this.

**Source patch** available at `patches/wine/0002-winewayland-drv-subsurface-before-vksurface.patch`.

**Limitation**: Only fixes main window. Child window previews still gray (separate wl_surfaces per HWND needed — Wine source change).

### CEF Import Dialog Workaround: `fix_createwindow.dll`
An AppInit DLL converts CEF `WS_CHILD` windows to `WS_POPUP`, giving them their own `xdg_toplevel`. This avoids the subsurface rendering path entirely.

**Required CEF flags**: `--in-process-gpu` (NOT `--disable-gpu`).

**Remaining problem**: Selecting a folder in the import dialog freezes the app on Wayland (main thread zombie). X11 works fine.

---

## Issue 2: X11 Flickering (NVIDIA 580.159.03)

NVIDIA driver 580.159.03 bypasses both Vulkan Present and GLX Present vsync. This causes persistent tearing/flickering on X11 that cannot be fixed from userspace.

**Workaround**: Use X11 for most tasks (the flicker affects only the Develop live preview). Use Wayland for flicker-free Develop work. X11 is the currently **recommended** mode because import, previews, and Library histogram all work.

---

## Issue 3: Develop Histogram — CameraRaw GPU Probe Failure

**Root cause (corrected)**: The DXVK/vkd3d-proton conflict theory was **incorrect**. The real root cause of the blank Develop histogram (and ALL other broken features on X11) is CameraRaw's GPU probe failing at startup. When CameraRaw initializes, it attempts a GPU probe via a broken code path under Wine/Proton. This corrupts GPU compute state, causing blank histograms, gray previews, and import freezes.

**Fix — GPU Pref Trick**: Launch Lightroom with `GPUManagerPref = "off"` in preferences → CameraRaw skips its broken startup GPU probe entirely. After Lightroom is fully loaded, enable GPU in Preferences → Performance → CameraRaw re-initializes via a **working** code path. Both D3D11 and D3D12 compute backends work correctly after this re-init.

**Status**: ✅ Develop histogram works on both X11 and Wayland with the GPU pref trick.

---

## Recommended Configuration

| Mode | Import | Previews | Library Histo | Develop Histo | Develop | Speed |
|------|--------|----------|---------------|---------------|---------|-------|
| **X11 (GPU pref trick)** 🏆 | ✅ | ✅ | ✅ (GPU) | ✅ (GPU) | ⚠️ flicker | Fast |
| Wayland (GPU pref trick) | ❌ freeze | ❌ gray | ✅ (GPU) | ✅ (GPU) | ✅ smooth | Medium |

**Launcher behavior**: Runs `gpu_pref_patcher.py off` before launch to set GPU=OFF in preferences. After Lightroom loads, the user enables GPU in Preferences → Performance.

---

## System

- Fedora 44 (GNOME 50.1), Arch Linux (Hyprland + Caelestia)
- Proton: GE-Proton10-34
- Lightroom Classic 13.x

## What's in this repo

| Directory | Contents |
|-----------|----------|
| `scripts/` | Launchers (X11 + Wayland), binary patch tool, download-stubs |
| `patches/wine/` | Wine source patches (d3d11 + winewayland.drv) |
| `patches/fix_createwindow.c` | AppInit DLL for CEF import dialog |
| `patches/libwl_*.c` | LD_PRELOAD alternatives (for reference) |
| `docs/ROOT_CAUSE.md` | Full root cause analysis |
| `dxvk.conf` | DXVK configuration |
| `stubs/` | CC stub DLL download instructions |

## See also

- [README.md](README.md) — Quick start and status
- [GUIDE.md](GUIDE.md) — Full setup guide
- [KNOWN_ISSUES.md](KNOWN_ISSUES.md) — Detailed issue tracking
- [AGENTS.md](AGENTS.md) — Complete session knowledge base

## AI Disclosure

Developed with assistance from opencode AI coding agent.

## Submit to:
1. **WineHQ Bugzilla** — winewayland.drv component
2. **GE-Proton GitHub** — https://github.com/GloriousEggroll/proton-ge-custom/issues
