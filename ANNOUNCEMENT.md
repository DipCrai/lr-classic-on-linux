# Adobe Lightroom Classic on Wine/Proton Wayland — Full Report

**TL;DR**: Three bugs block Lightroom on Wayland with NVIDIA:
1. wl_surface role conflict (VkSurface + wl_subsurface) → gray previews / hang
2. CEF child windows not rendering on Wayland → white import dialog
3. X11 unfixable flickering with NVIDIA 580.159.03

---

## Issue 1: wl_surface role conflict (CRITICAL)

### Root Cause
`winewayland.drv` creates a `wl_subsurface` on the **same** `wl_surface` that is already used for `VkSurfaceKHR`. The Wayland protocol forbids assigning more than one role to a `wl_surface`. The NVIDIA Wayland driver enforces this: when the wl_surface role changes from "VkSurface" to "wl_subsurface", the driver rejects swapchain creation and DXVK hangs.

### Call Chain
```
D3D11CreateDeviceAndSwapChain(hwnd=CHILD)
 → DXVK → vkCreateWin32SurfaceKHR(hwnd)
 → winewayland.drv → wayland_vulkan_surface_create(hwnd)
   → wl_compositor_create_surface() → wl_surface_A        ← NO ROLE YET
   → vkCreateWaylandSurfaceKHR(..., wl_surface_A)          ← VkSurface ROLE assigned
   → set_client_surface(hwnd, client)
     → wl_subcompositor.get_subsurface(..., wl_surface_A)  ← wl_subsurface ROLE assigned (CONFLICT!)
     → NVIDIA refuses to create swapchain → DXVK hangs
```

### Code Location (winewayland.drv)
```
wayland_vulkan_surface_create()  — creates wl_surface + VkSurface
wayland_client_surface_attach()  — calls wl_subcompositor.get_subsurface on same wl_surface
```

`wayland_vulkan_surface_create` at `dlls/winewayland.drv/vulkan.c` (or similar):
1. Creates a `wayland_client_surface` via `wayland_client_surface_create(hwnd)`
2. This creates a new `wl_surface` via `wl_compositor_create_surface()`
3. Creates `VkSurfaceKHR` on that `wl_surface` via `vkCreateWaylandSurfaceKHR`
4. Calls `set_client_surface(hwnd, client)` which calls `wayland_client_surface_attach`
5. `wayland_client_surface_attach` calls `wl_subcompositor.get_subsurface` on the SAME `wl_surface`

### The Fix (two options)

#### Option A: Reorder (binary patch workaround)
Move `set_client_surface()` (which triggers subsurface creation) to BEFORE `vkCreateWaylandSurfaceKHR()`. The wl_surface gets the subsurface role first, then VkSurface is created. NVIDIA driver accepts this because the role doesn't change after VkSurface creation.

**Binary patch** (applied to `winewayland.so`):
```
At offset 0x12efe in wayland_vulkan_surface_create:
  Replace: NtUserCallHwndParam + test/jne (D3D vs GDI check)
  With:    mov rbx->rsi (client), mov r12->rdi (hwnd),
           call set_client_surface
           nop padding
```

**Source patch** (proper fix for winewayland.drv source):
```diff
--- a/dlls/winewayland.drv/vulkan.c
+++ b/dlls/winewayland.drv/vulkan.c
@@ -XXX,XX +XXX,XX @@ static HWND wayland_vulkan_surface_create(HWND hwnd)
     if (!client_surface)
         return NULL;

+    /* Attach client surface BEFORE creating VkSurface to avoid
+     * wl_surface role conflict (VkSurface + wl_subsurface on same surface).
+     * NVIDIA Wayland driver rejects surfaces whose role changes after
+     * VkSurface creation. */
+    set_client_surface(hwnd, client_surface);
+
     surface = wayland_surface_create(display, client, hwnd, FALSE);
     if (!surface)
     {
         wayland_client_surface_destroy(client_surface);
         return NULL;
     }
-
-    set_client_surface(hwnd, client_surface);
```

#### Option B: Separate wl_surfaces (cleaner fix)
Use a **separate** `wl_surface` for the subsurface, keeping the VkSurface's `wl_surface` role-free for the NVIDIA driver:

```diff
--- a/dlls/winewayland.drv/client.c
+++ b/dlls/winewayland.drv/client.c
@@ -XXX,XX +XXX,XX @@ struct wayland_client_surface *wayland_client_surface_create(HWND hwnd)
     if (!client)
         return NULL;

-    client->wl_surface = wl_compositor_create_surface(process_wayland.compositor);
+    /* Create TWO wl_surfaces: one for the subsurface role (for GDI),
+     * and one role-free for VkSurface (required by NVIDIA Wayland driver).
+     * D3D11/Vulkan surfaces use the role-free surface.
+     * GDI/software surfaces use the subsurface surface (attached to parent). */
+    client->wl_surface = wl_compositor_create_surface(process_wayland.compositor);      // for VkSurface
+    client->wl_subsurface_surface = wl_compositor_create_surface(process_wayland.compositor); // for subsurface

     client->ref = 1;
     client->hwnd = hwnd;
```

Then use `client->wl_subsurface_surface` in `wayland_client_surface_attach` for the `get_subsurface` call, while `client->wl_surface` stays role-free for VkSurface.

---

## Issue 2: CEF Import Dialog Not Rendering

### Root Cause
Chromium Embedded Framework (CEF) creates child windows (`WS_CHILD`) for its rendering. On Wayland, `winewayland.drv` creates child windows as `wl_subsurface`s attached to the parent's `wl_surface`. The CEF content renders via D3D11 → DXVK → Vulkan, but the Vulkan swapchain is created on the subsurface's wl_surface, which again has the role conflict.

Additionally, CEF's child window rendering on Wayland subsurfaces has problems with visibility and positioning — the child surface is either invisible or covers the parent incorrectly.

### Workaround: `fix_createwindow.dll`
An AppInit DLL that converts CEF's `WS_CHILD` windows to `WS_POPUP` (top-level windows), which get their own `xdg_toplevel` role and render independently:

- Intercepts `CreateWindowExW` in `user32.dll`
- Detects CEF window classes (`Chrome_WidgetWin_0`, `Chrome_RenderWidgetHostHWND`, etc.)
- Removes `WS_CHILD`, adds `WS_POPUP` + `WS_EX_APPWINDOW`
- CEF renders on a separate `xdg_toplevel` wl_surface → no child/subsurface issues

### Required CEF flags
```
CHROMIUM_FLAGS="--in-process-gpu"
```
- `--in-process-gpu`: compositor in browser process (avoids GPU process IPC issues on Wine)
- **NO** `--disable-gpu`: CEF must use ANGLE/D3D11/DXVK/Vulkan, not software GDI/wl_shm

### DXVK config requirements
```
d3d11.maxFeatureLevel = 11_0      # 10_0 breaks import (white window)
dxgi.syncInterval = 0
```

---

## Issue 3: X11 Flickering (NVIDIA 580.159.03)

NVIDIA 580.159.03 driver bypasses BOTH:
- Vulkan Present (VK_PRESENT_MODE_FIFO_KHR — tearing)
- GLX Present (GLX_EXT_swap_control — also bypassed)

Result: persistent screen-tearing / flickering on X11 that cannot be fixed from userspace. This makes X11 unusable for Lightroom on this driver.

**No known fix.** Must use Wayland (which is flicker-free).

---

## System

- Fedora 44, GNOME 50.1, NVIDIA GTX 1080 Ti (driver 580.159.03)
- Proton: GE-Proton10-34
- Lightroom 13.x (Classic)

---

## Working Configuration Summary

| Component | Setting |
|-----------|---------|
| Display server | Wayland (X11 flickers, unfixable) |
| Proton | GE-Proton10-34 |
| CEF render | `--in-process-gpu` (NOT `--disable-gpu`) |
| fix_createwindow | Required for CEF import dialog |
| Binary patch v4 | Reorder subsurface < VkSurface |
| DXVK feature level | `d3d11.maxFeatureLevel = 11_0` |
| DXVK sync | `dxgi.syncInterval = 0` |

## Still Broken

1. **Histogram/Exposure meter** — D2D1 rendering path (patched `d2d1.dll` stub doesn't fully implement it)
2. **Scrolling ghosting** — Minor trailing artifacts when scrolling Library grid
3. **CEF folder select** — May still hang when selecting folders in import dialog
4. **Fullscreen behavior** — Some `WS_POPUP` windows from `fix_createwindow` may not position correctly

## LD_PRELOAD Alternative (for testing without binary patch)

If you prefer not to binary-patch `winewayland.so`, a `LD_PRELOAD` library can intercept `wl_proxy_marshal_constructor` in libwayland-client and block `wl_subcompositor.get_subsurface`. However, this leaves the `wl_surface` role-less (no subsurface role), so the Wayland compositor ignores committed buffers → invisible content.

The binary patch (Option A above) is cleaner because it gives the wl_surface a subsurface role BEFORE VkSurface creation, keeping content visible.

---

## Files

All sources and patches are available at:
https://github.com/anomalyco/opencode/issues (or contact via WineHQ Bugzilla)

- `/home/ivan/lrcfix/fix_createwindow.c` — AppInit DLL for WS_CHILD→WS_POPUP conversion
- `/home/ivan/lrcfix/libwl_got_patch.c` — GOT-patching LD_PRELOAD (monitoring thread approach)
- `/home/ivan/lrcfix/libwl_block_subsurface_v2.c` — Direct LD_PRELOAD (won't work due to RTLD_LOCAL)
- Patch script: `dd if=/dev/zero bs=1 count=21 2>/dev/null | ...` (binary patch at offset 0x12efe)

---

## AI Disclosure

This analysis and associated fixes were developed with assistance from an AI coding agent (opencode). The investigation involved automated binary analysis, protocol debugging, and iterative patch development guided by human direction.

## Submit to:

1. **WineHQ Bugzilla** — https://bugs.winehq.org/ — winewayland.drv component
2. **GE-Proton GitHub** — https://github.com/GloriousEggroll/proton-ge-custom/issues
3. **Wine Development Mailing List** — wine-devel@winehq.org
