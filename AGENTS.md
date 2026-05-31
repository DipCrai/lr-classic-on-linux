# Adobe Lightroom Classic on Proton — Agent Knowledge Base

## TL;DR Current State (2026-05-31)
- **Published**: https://github.com/DipCrai/lr-classic-on-linux
- **X11 (recommended)**: Main ✅, Import ✅, Previews ✅, Library histo (GPU3) ✅, Develop ⚠️ flicker, Develop histo ❌
- **Wayland**: Main ✅, Develop ✅, Import ❌ freeze, Previews ❌ gray, Histo ❌
- **Best X11**: TempDisableGPU3 only → D3D11 GPU, Develop histo ❌ (CPU workaround)
- **Root cause confirmed**: DXVK + vkd3d-proton in-process conflict — same on NVIDIA AND software Vulkan
- **System**: Fedora 44, GNOME 50.1, GTX 1080 Ti (Pascal), NVIDIA 580.159.03, GE-Proton10-34

## Key Findings
- **CreateDirect3D11DeviceFromDXGIDevice** — Wine patch implemented (0001), CameraRaw needs it
- **Binary patches (winewayland.so)**: subsurface reorder (0x12efe) + visibility bypass (0x258be)
- **GPU2=D3D11 compute, GPU3=D3D12 compute**: GPU3-only is default X11 config
- **Develop histogram only works**: CPU (TempDisableGPU2+3) or D3D12 alone (breaks everything else)

## What NOT to do
1. Do NOT replace d3d11.dll with proxy (breaks previews)
2. Do NOT replace dxgi.dll (DXVK bypasses PE exports)
3. Do NOT use LD_PRELOAD for Wayland (RTLD_LOCAL prevents interception)
4. Do NOT intercept wl_proxy_marshal (non-constructor) — ABI trap
5. Do NOT call dlsym(RTLD_NEXT) from within interceptor
6. Do NOT use Virtual Desktop / Gamescope on Wayland
7. Do NOT use --disable-gpu for CEF
8. Do NOT use wine64 directly — always proton run
