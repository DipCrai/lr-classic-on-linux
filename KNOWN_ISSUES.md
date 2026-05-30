# Known Issues

## 1. CEF Import Dialog — Folder Select Freeze

**Status**: ❌ Broken — app freezes on folder selection.

The import dialog opens and CEF content is visible (thanks to `fix_createwindow.dll` converting WS_CHILD→WS_POPUP). However, selecting a folder in the dialog **causes the main thread to become a zombie** while render threads remain alive. The app becomes completely unresponsive.

**Possible causes** (unconfirmed):
- Thumbnail swapchain creation triggers new D3D11 surfaces → some surfaces still fail
- D3D12/vkd3d code path (not patched by our binary patch)
- D2D1 histogram/exposure meter rendering (known broken stub)
- Media Foundation stub (`mfplat.dll`) causing deadlock
- CEF IPC deadlock with `--in-process-gpu`

**No known fix yet.** The binary patch (subsurface reorder) is a necessary foundation but not sufficient.

## 2. Image Previews

**Status**: ❓ UNTESTED on Wayland.

The binary patch (reorder subsurface before VkSurface) was designed to fix preview rendering, but it has **never been tested**. Previews may still be gray/invisible.

On X11, previews work correctly (real X11 child windows, no role conflict).

## 3. Histogram / Exposure Meter (D2D1)

**Status**: ❌ Broken on both X11 and Wayland.

The histogram and exposure meter use D2D1 (Direct2D) for rendering. The patched `d2d1.dll` from the CC stubs doesn't fully implement all D2D1 effects. No known fix without implementing the missing D2D1 functionality.

## 4. Scrolling Ghosting / Trailing

**Status**: ⚠️ Minor artifact on Wayland.

When scrolling in the Library grid, some trailing/ghosting artifacts appear. Likely related to `dxgi.syncInterval = 0` (immediate present) + wl_subsurface presentation timing. Try `dxgi.syncInterval = 1` to test.

## 5. Fullscreen Behavior

**Status**: ⚠️ Inconsistent.

WS_POPUP windows created by `fix_createwindow.dll` may not position correctly in fullscreen mode. Window decorations may be missing or incorrect.

## 6. NVIDIA X11 Flickering

**Status**: ❌ UNFIXABLE.

NVIDIA driver 580.159.03 bypasses both Vulkan Present (VK_PRESENT_MODE_FIFO_KHR) and GLX Present (GLX_EXT_swap_control), causing persistent tearing/flickering on X11. This is a driver bug.

**Workaround**: Use Wayland only.
