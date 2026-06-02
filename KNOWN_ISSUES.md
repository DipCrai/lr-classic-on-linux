# Known Issues

## 1. Develop Histogram (X11)

**Status**: ✅ FIXED on X11 with GPU pref trick. ✅ Wayland: works with GPU pref trick (same fix).

**Root cause**: The Develop histogram blank was NOT a DXVK/vkd3d-proton conflict. The real root cause was CameraRaw's GPU probe failing at startup, corrupting GPU compute state. The TempDisable experiments were testing different states of a broken GPU initialization, not a conflict between backends.

**Fix**: Same GPU pref trick as everything else — launch with `GPUManagerPref = "off"`, toggle ON in Preferences → CameraRaw initializes cleanly → both D3D11 and D3D12 compute work correctly → Develop histogram renders.

**Previous (incorrect) analysis**: Extensive testing showed different TempDisable combinations giving different results, which was interpreted as DXVK/vkd3d-proton conflict. In reality, CameraRaw's GPU probe was failing nondeterministically depending on timing and pre-existing TempDisable state. The "GPU2-only → Develop histogram works" result was actually CameraRaw initializing in a degraded state that happened to leave D3D12 compute accessible.

**Wayland**: Develop histogram works with the GPU pref trick (same as X11). Library histogram also works. Only import ❌ and previews ❌ remain broken due to wl_surface role conflict.

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

## 4. Library Histogram

**Status**: ✅ X11: works (GPU pref trick). ✅ Wayland: works (GPU pref trick).

**Root cause**: CameraRaw's GPU probe during startup fails (deadlock/black screen). Library histogram rendering via D2D1 requires CameraRaw GPU to be initialized.

**GPU Pref Trick fix**: Launch with `GPUManagerPref = "off"` in Lightroom preferences → CameraRaw skips the broken startup probe. When user enables GPU in Preferences, CameraRaw re-initializes via the working code path → histogram renders. The launcher handles this automatically via `gpu_pref_patcher.py off`.

Wayland: GPU trick fixes histogram ✅ but import still freezes ❌ and previews still gray ❌.

**Previous (incorrect) understanding**: Was thought to be a D2D1 stub issue (patched d2d1.dll). Actually, the d2d1 stub works fine — GPU just wasn't initializing.

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
| Develop histogram | ✅ (GPU pref trick) | ✅ (GPU pref trick) |
| Import dialog | ✅ | ❌ (freeze) |
| Previews | ✅ | ❌ (gray) |
| Library histogram | ✅ (GPU pref trick) | ✅ (GPU pref trick) |
| Develop module | ⚠️ (flicker) | ✅ |
| Fullscreen | ⚠️ | ⚠️ |
