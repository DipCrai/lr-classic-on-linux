# Known Issues

## 1. Histogram / Exposure Meter (D2D1)

**Status**: Broken on both X11 and Wayland.

The histogram and exposure meter use D2D1 (Direct2D) for rendering. The patched `d2d1.dll` from the CC stubs doesn't fully implement all D2D1 effects. No known fix without implementing the missing D2D1 functionality.

## 2. Scrolling Ghosting / Trailing

**Status**: Minor artifact on Wayland.

When scrolling in the Library grid, some trailing/ghosting artifacts appear. Likely related to `dxgi.syncInterval = 0` (immediate present) + wl_subsurface presentation timing.

## 3. CEF Import Dialog - Folder Select

**Status**: May hang when selecting folders in the import dialog.

The fix_createwindow.dll converts CEF's WS_CHILD windows to WS_POPUP. This works for the dialog UI but folder selection (which creates new child dialogs) may still trigger the wl_surface role conflict in the new windows.

## 4. Fullscreen Behavior

**Status**: Inconsistent.

WS_POPUP windows created by fix_createwindow may not position correctly in fullscreen mode. Window decorations may be missing or incorrect.

## 5. NVIDIA X11 Flickering

**Status**: UNFIXABLE.

NVIDIA driver 580.159.03 bypasses both Vulkan Present (VK_PRESENT_MODE_FIFO_KHR) and GLX Present (GLX_EXT_swap_control), causing persistent tearing/flickering on X11. This is a driver bug.

**Workaround**: Use Wayland only.
