# Adobe Lightroom Classic on Wine/Proton — Full Report

**TL;DR**: Four issues block Lightroom on Linux:
1. **wl_surface role conflict** (VkSurface + wl_subsurface) → gray previews on Wayland
2. **CEF child windows** → white/frozen import dialog on Wayland
3. **X11 flickering** → NVIDIA 580.159.03 bypasses vsync on X11
4. **DXVK + vkd3d-proton conflict** → Develop histogram blank on Pascal (confirmed in-process bug)

**Current recommendation**: Use **X11** with GPU3-only config (TempDisableGPU3) for a stable workflow. Use Wayland for flicker-free Develop module work.

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

## Issue 3: Develop Histogram — DXVK + vkd3d-proton Conflict (Pascal)

**Root cause confirmed**: DXVK (Vulkan D3D11) and vkd3d-proton (Vulkan D3D12) corrupt each other when both active in the same process. Confirmed on both NVIDIA Pascal and software Vulkan (llvmpipe/LVP) — not a GPU driver bug.

**Impact**: The histogram needs both D3D11 (Library) and D3D12 (Develop) GPU compute. They cannot coexist. GPU3-only (D3D12 off) gives a working D3D11 GPU for everything except Develop histogram, which falls back to CPU.

**No known fix**. Upstream DXVK/vkd3d-proton investigation needed.

**Workaround**: Launcher scripts automatically create TempDisableGPU2+3 for CPU fallback. For GPU acceleration, remove TempDisableGPU3 (keep only TempDisableGPU2 or neither — but both active corrupts).

---

## Recommended Configuration

| Mode | Import | Previews | Library Histo | Develop Histo | Develop | Speed |
|------|--------|----------|---------------|---------------|---------|-------|
| **X11 GPU3-only** 🏆 | ✅ | ✅ | ✅ (GPU) | ❌ (CPU) | ⚠️ flicker | Fast |
| X11 CPU fallback | ✅ | ✅ | ✅ (CPU) | ✅ (CPU) | ⚠️ flicker | Slow |
| Wayland GPU3 | ❌ freeze | ❌ gray | ❌ | ❌ | ✅ smooth | Medium |

**Default launcher behavior**: Creates TempDisableGPU2+3 (CPU fallback) with a background watcher that restores them if CameraRaw deletes them. This is safest but slowest. Adjust by removing/commenting the watcher section in the launcher script.

---

## System

- Fedora 44, GNOME 50.1, NVIDIA GTX 1080 Ti (Pascal, driver 580.159.03)
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
3. **DXVK GitHub** — D3D11 + D3D12 in-process conflict
4. **vkd3d-proton GitHub** — Pascal D3D12 compute
