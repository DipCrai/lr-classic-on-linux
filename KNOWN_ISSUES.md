# Known Issues

## 1. CEF Import Dialog — Folder Select Freeze (Wayland only)

**Status**: ❌ Wayland: freezes on folder select. ✅ X11: works.

On Wayland, the import dialog opens and CEF content is visible (thanks to `fix_createwindow.dll`). However, selecting a folder **freezes the main thread** while render threads stay alive. The app becomes completely unresponsive.

On X11, the import dialog works correctly.

**Possible causes** (unconfirmed):
- Thumbnail swapchain triggers new D3D11 surfaces → some still fail
- D3D12/vkd3d code path (not patched by binary patch)
- D2D1 histogram rendering (known broken stub)
- Media Foundation stub (`mfplat.dll`) causing deadlock
- CEF IPC deadlock with `--in-process-gpu`

**No known fix yet.**

## 2. Image Previews (Wayland only)

**Status**: ❌ Wayland: gray rectangles in filmstrip/Library grid. ✅ X11: works.

On Wayland, the main image and Develop module render correctly, but small previews in the bottom filmstrip and Library grid are gray. The binary patch (subsurface reorder) was designed to fix this but is not sufficient.

The root cause is the same `wl_surface` role conflict between `wl_subsurface` and `VkSurfaceKHR` — the binary patch avoids the hang but the subsurface role may still interfere with certain swapchain configurations.

## 3. Histogram / Exposure Meter (D2D1)

**Status**: ❌ Broken on both X11 and Wayland.

The histogram and exposure meter use D2D1 (Direct2D). The patched `d2d1.dll` from the CC stubs doesn't fully implement all D2D1 effects. No known fix.

## 4. Live Preview Flicker (X11 only)

**Status**: ⚠️ Develop live preview flickers on X11.

NVIDIA driver 580.159.03 bypasses both Vulkan Present (VK_PRESENT_MODE_FIFO_KHR) and GLX Present (GLX_EXT_swap_control), causing tearing/flickering specifically in the Develop module live preview.

Use Wayland for a flicker-free Develop experience.

## 5. Scrolling Ghosting / Trailing (Wayland)

**Status**: ⚠️ Minor artifact on Wayland.

When scrolling in the Library grid, some trailing/ghosting artifacts appear. Likely related to `dxgi.syncInterval = 0` + wl_subsurface presentation timing.

## 6. Fullscreen Behavior

**Status**: ⚠️ Inconsistent on both.

WS_POPUP windows created by `fix_createwindow.dll` may not position correctly in fullscreen mode. Window decorations may be missing or incorrect.

## 7. X11 Intermittent Crash

**Status**: ⚠️ Rare `X_CopyArea` crash under XWayland.

When running Lightroom under XWayland on NVIDIA, an infrequent `X_CopyArea` `BadMatch` error may occur. This is an XWayland GLAMOR bug (#1317) triggered by child window compositing. Restarting usually resolves it.
