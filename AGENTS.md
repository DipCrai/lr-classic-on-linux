# Adobe Lightroom Classic on Proton — Agent Knowledge Base

## TL;DR Current State (2026-05-31, Session 6)
- **X11 (recommended)**: Main ✅, Import ✅, Previews ✅, Library histo ✅ (GPU3), Develop ⚠️ flicker, Develop histo ❌ (blank)
- **Wayland**: Main ✅, Develop ✅, Import ❌ freeze, Previews ❌ gray, Histo ❌
- **GPU3-only config**: Best X11 — D3D12 off, D3D11 via DXVK. All GPU except Develop histo.
- **CPU fallback**: TempDisableGPU2+3 both set — everything works, slow
- **System**: Fedora 44, GNOME 50.1, GTX 1080 Ti (Pascal), NVIDIA 580.159.03, GE-Proton10-34

## Session 6 Findings (Develop Histogram Root Cause)

### D3D12 + D3D11 compute CONFIRMED incompatible
- Tested on NVIDIA (580.159.03) AND software Vulkan (LVP/llvmpipe) — SAME corruption
- Not a GPU driver bug — DXVK + vkd3d-proton in-process software conflict
- Tested: GPU3-only ✅/❌, GPU2-only ❌/✅, both on ❌/❌, both off ✅/✅
- WineD3D + vkd3d-proton ❌, Wine built-in d3d12 (CPU) ✅, D3D12 no-op proxy ❌
- Cache files not the cause (tested with DXVK_STATE_CACHE=0 + VKD3D_SHADER_CACHE=disable)
- **Fix**: Unknown — needs upstream DXVK/vkd3d-proton investigation

### CreateDirect3D11DeviceFromDXGIDevice
- CameraRaw delay-imports from d3d11.dll — not exported by DXVK or Wine
- Wine source patch committed: `patches/wine/0001-*`
- Without export: CameraRaw cannot pass GPU probe stage 1

### Binary patches (winewayland.so, GE-Proton10-34)
- Patch 1 (0x12efe): Subsurface reorder before VkSurface creation
- Patch 2 (0x258be): Visibility bypass (75→eb, skip GDI block)
- Both applied by `apply_patch.py`
- Limitation: child window previews still gray (same wl_surface dual role)

### /mnt/Penis mount issue
- NTFS RO due to Windows fast startup dirty bit
- `ntfsfix` cleaned, but FUSE connections corrupted by abort/lazy-umount
- Reboot required to clear — `sudo mount -a` after reboot works
- Repo files are on rootfs at `/home/ivan/lrcfix/`, workflow unaffected

### GPU config semantics
- TempDisableGPU2 = D3D11 compute off
- TempDisableGPU3 = D3D12 compute off
- GPU0=OpenCL, GPU1=OpenGL, GPU2=D3D11 compute, GPU3=D3D12 compute
- Config dir: `.../CameraRaw/GPU/Adobe Photoshop Lightroom Classic/`

### Best configs
| Mode | Library | Develop preview | Develop histo | Previews | Import | Speed |
|------|---------|----------------|---------------|----------|--------|-------|
| GPU3-only (X11) 🏆 | ✅ | ⚠️ flickers | ❌ blank | ✅ | ✅ | Fast |
| CPU (GPU2+3 off) | ✅ | ✅ | ✅ CPU | ✅ | ✅ | Slow |
| Wayland GPU3 | ✅ | ✅ | ❌ | ❌ gray | ❌ freeze | Medium |

## What NOT to do
1. Do NOT replace d3d11.dll with proxy — HWND replacement breaks all previews
2. Do NOT replace dxgi.dll — DXVK bypasses PE exports
3. Do NOT use LD_PRELOAD for Wayland — RTLD_LOCAL prevents interception
4. Do NOT intercept wl_proxy_marshal (non-constructor) — ABI trap
5. Do NOT call dlsym(RTLD_NEXT) from within interceptor — corrupts va_list
6. Do NOT use Virtual Desktop / Gamescope on Wayland
7. Do NOT use --disable-gpu for CEF — must be --in-process-gpu
8. Do NOT use wine64 directly — always proton run

## Key Decisions
- **GPU3-only default for X11**: Everything works on D3D11 GPU
- **Proxy must be transparent**: No D3D11CreateDeviceAndSwapChain override
- **Launcher defaults**: TempDisableGPU2+3 (CPU fallback) with watcher — safe but slow
- **For GPU acceleration**: Comment out watcher, set only TempDisableGPU3
- **Wayland child fix**: Needs separate wl_surfaces per HWND (Wine source change)
- **D3D12 compute unfixable**: Pure stub would trigger full CPU fallback (same as Wine d3d12)

## What was pushed to repo this session
1. `patches/wine/0001-*` — d3d11 CreateDirect3D11DeviceFromDXGIDevice
2. `patches/wine/0002-*` — winewayland subsurface reorder source patch
3. `scripts/apply_patch.py` — multi-patch support (subsurface + visibility)
4. `scripts/launch_lightroom.sh` — merged fixes, histogram watcher
5. `scripts/launch_lightroom_x11.sh` — histogram watcher, updated header
6. `AGENTS.md` — this file
7. Updated: README.md, GUIDE.md, KNOWN_ISSUES.md, ANNOUNCEMENT.md, docs/ROOT_CAUSE.md

## Archived experimental files
- `/home/ivan/lrcfix/archived/d3d12_proxy.c` — D3D12 no-op proxy (vtable hooks)
- `/home/ivan/lrcfix/archived/d3d12_stub.c` — D3D12 pure stub
- `/home/ivan/lrcfix/archived/session6.md` — raw session logs
- `/home/ivan/lrcfix/archived/d3d11_proxy_v2.c` — d3d11 proxy v2
- `/home/ivan/lrcfix/archived/fix_createwindow_x11_v2.c` — X11 variant v2

## /mnt/Penis
- NTFS-3G, UUID=663D2410729FE1D8, mounted at /mnt/Penis (fstab: lowntfs-3g)
- After reboot: `sudo mount -a` mounts RW (ntfsfix already cleared dirty bit)
- Lightroom path: `/mnt/Penis/Lightroom/Adobe/Adobe Lightroom Classic/Lightroom.exe`
- CameraRaw GPU config: `.../CameraRaw/GPU/Adobe Photoshop Lightroom Classic/Camera Raw GPU Config.txt`
