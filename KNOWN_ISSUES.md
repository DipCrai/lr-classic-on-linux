# Known Issues

## 1. Develop Histogram — DXVK + vkd3d-proton Conflict (Pascal)

**Status**: ❌ Develop histogram blank on all configs except CPU fallback.

**Root cause**: DXVK (Vulkan D3D11) and vkd3d-proton (Vulkan D3D12) corrupt each other when both active in the same process. Confirmed on NVIDIA GTX 1080 Ti (Pascal, driver 580.159.03) AND on software Vulkan (llvmpipe/LVP) — not a GPU driver bug, but a DXVK/vkd3d-proton in-process software conflict.

**Proof**:
- GPU3-only (D3D12 off, D3D11 on) → works except Develop histogram ❌
- GPU2-only (D3D11 compute off, D3D12 on) → Develop histogram ✅, everything else ❌
- Both on → Develop preview ✅ only, everything else broken ❌
- Both off (CPU) → everything works ✅ but slow
- Wine built-in d3d12 (no vkd3d-proton) → full CPU fallback ✅
- D3D12 no-op proxy (vtable hooks, real vkd3d-proton loaded) → corruption ❌
- LVP software Vulkan for everything → SAME corruption ❌

**No known fix**. Upstream DXVK/vkd3d-proton investigation needed.

**Workaround**: The launcher scripts create TempDisableGPU2+3 in CameraRaw's GPU config directory, forcing CPU fallback for all compute (works, slower).

## 2. CEF Import Dialog — Folder Select Freeze (Wayland)

**Status**: ❌ Wayland: freezes on folder select. ✅ X11: works.

On Wayland, the import dialog opens and CEF content is visible. Selecting a folder freezes the main thread completely. All render threads stay alive (DXVK + CEF GPU process). X11 works fine.

**Possible causes** (unconfirmed):
- Thumbnail swapchain triggers new D3D11 surfaces that still fail
- D3D12/vkd3d code path (not patched by binary patch)
- D2D1 histogram rendering (known broken stub)
- mfplat stub deadlock
- CEF IPC deadlock with `--in-process-gpu`

## 3. Image Previews (Wayland)

**Status**: ❌ Wayland: gray rectangles in filmstrip/Library grid. ✅ X11: works.

On Wayland, the main image and Develop module render correctly, but small previews are gray. The binary patch (subsurface reorder) avoids the hang but child window wl_surfaces still get conflicting roles — subsurface + VkSurface on the same wl_surface. Fix requires separate wl_surfaces per HWND (Wine source change in winewayland.drv).

## 4. Library Histogram (Wayland)

**Status**: ❌ Wayland: broken. ✅ X11: works (GPU3-only config).

Wayland's wl_surface role conflict affects all D3D11 swapchains, including the histogram render target. X11 with GPU3-only config works because D3D12 is disabled and D3D11 compute runs via DXVK.

## 5. Live Preview Flicker (X11)

**Status**: ⚠️ Develop live preview flickers on X11.

NVIDIA driver 580.159.03 bypasses both Vulkan Present (VK_PRESENT_MODE_FIFO_KHR) and GLX Present, causing tearing/flickering. Use Wayland for Develop work.

## 6. Scrolling Ghosting (Wayland)

**Status**: ⚠️ Minor trailing artifacts when scrolling Library grid.

Likely related to `dxgi.syncInterval = 0` + wl_subsurface presentation timing.

## 7. Fullscreen Behavior

**Status**: ⚠️ Inconsistent on both.

WS_POPUP windows created by `fix_createwindow.dll` may not position correctly in fullscreen mode.

## 8. X11 Intermittent Crash

**Status**: ⚠️ Rare `X_CopyArea` BadMatch under XWayland.

XWayland GLAMOR bug (#1317) triggered by child window compositing. Restart resolves it.

## Summary Table

| Issue | X11 | Wayland |
|-------|-----|---------|
| Develop histogram | ❌ (blank) | ❌ |
| Import dialog | ✅ | ❌ (freeze) |
| Previews | ✅ | ❌ (gray) |
| Library histogram | ✅ (GPU3-only) | ❌ |
| Develop module | ⚠️ (flicker) | ✅ |
| Fullscreen | ⚠️ | ⚠️ |
