# Adobe Lightroom Classic on Linux

Fixes for running **Adobe Lightroom Classic** on Linux with **Wine/Proton + Wayland**.

## Status

| Feature | Wayland | X11 |
|---------|---------|-----|
| Main UI | ✅ Works | ❌ Unfixable flickering |
| CEF Import Dialog | ⚠️ Works (with fix_createwindow) | ✅ Works |
| Image Previews | ⚠️ Works (with winewayland patch) | ✅ Works |
| Histogram | ❌ Broken (D2D1) | ❌ Broken (D2D1) |
| Develop module | ⚠️ Mostly works | ⚠️ Mostly works |
| Export | ✅ Works | ✅ Works |

## Root Cause

**The main bug**: `winewayland.drv` creates a `wl_subsurface` on the **same** `wl_surface` used by `VkSurfaceKHR`. Wayland forbids giving a surface multiple roles. The NVIDIA Wayland driver enforces this and refuses swapchain creation.

**Detailed analysis**: see [docs/ROOT_CAUSE.md](docs/ROOT_CAUSE.md)

## Fixes

### 1. winewayland.drv patch (reorder subsurface creation)

The subsurface must be created **before** `vkCreateWaylandSurfaceKHR`, not after. This avoids the role conflict:

```diff
+    set_client_surface(hwnd, client_surface);
     surface = wayland_surface_create(display, client, hwnd, FALSE);
-    set_client_surface(hwnd, client_surface);
```

See [patches/](patches/) for binary patch and source patch.

### 2. CEF Import Dialog (fix_createwindow.dll)

CEF child windows need to be top-level (`WS_POPUP` instead of `WS_CHILD`) to render on Wayland. The [fix_createwindow.dll](patches/fix_createwindow.c) intercepts `CreateWindowExW` and converts CEF windows.

### 3. DXVK Configuration

```ini
d3d11.maxFeatureLevel = 11_0
dxgi.syncInterval = 0
dxgi.deferSurfaceCreation = True
```

### 4. CEF Flags

```
CHROMIUM_FLAGS="--in-process-gpu"
```

**NO** `--disable-gpu` — CEF must use ANGLE/D3D11/DXVK/Vulkan.

## Quick Start

See [GUIDE.md](GUIDE.md) for full setup instructions.

## Known Issues

See [KNOWN_ISSUES.md](KNOWN_ISSUES.md)

## License

MIT
