# Adobe Lightroom Classic on Linux

Fixes and analysis for running **Adobe Lightroom Classic** on Linux via **Wine/Proton**.

## Status

| Feature | X11 (recommended) | Wayland |
|---------|-------------------|---------|
| Main window | ✅ | ✅ (patch required) |
| Import dialog | ✅ | ❌ (freezes on folder select) |
| Image previews | ✅ | ❌ (gray) |
| Library histogram | ✅ (GPU pref trick) | ✅ (GPU pref trick) |
| Develop histogram | ✅ (GPU pref trick) | ❌ |
| Develop module | ⚠️ (live preview flickers) | ✅ |

**GPU Pref Trick**: Launch with `GPUManagerPref = "off"` in Lightroom preferences — CameraRaw skips its broken startup GPU probe. Enable GPU in Lightroom settings → CameraRaw re-initializes via working code path. Everything works on X11 with this trick (import, previews, all histograms). Only Develop module flickering on X11 remains.

**Critical finding**: The DXVK/vkd3d-proton conflict theory was incorrect. The real root cause of ALL broken features on X11 was CameraRaw's GPU probe failing at startup, corrupting GPU compute state. When CameraRaw initializes cleanly (via the GPU toggle re-init path), both D3D11 and D3D12 compute backends work correctly.

## Quick Start

```bash
git clone https://github.com/DipCrai/lr-classic-on-linux.git
cd lr-classic-on-linux

# Apply binary patch (required for Wayland only)
python3 scripts/apply_patch.py

# Set up prefix and install VC++ runtimes
WINEPREFIX=$HOME/.lightroom_prefix/pfx winetricks -q vcrun2022

# Download and install CC stub DLLs
./scripts/download-stubs.sh

# Launch!
./scripts/launch_lightroom_x11.sh   # X11 (stable, recommended)
./scripts/launch_lightroom.sh       # Wayland (flicker-free, partial)
```

Full setup: [GUIDE.md](GUIDE.md)

## Root Causes

| Issue | Root Cause | Status |
|-------|------------|--------|
| Gray previews (Wayland) | Same `wl_surface` gets both `wl_subsurface` + `VkSurfaceKHR` roles — role conflict | ⚠️ Binary patch avoids hang but gray persists |
| Import freeze (Wayland) | CEF folder select deadlock | ❌ Unresolved |
| Develop histogram blank | DXVK + vkd3d-proton in-process conflict on Pascal | ❌ Use CPU (TempDisableGPU2+3) |
| X11 flickering | NVIDIA 580.159.03 driver bypasses vsync | ❌ Use Wayland for Develop |
| Library histogram ✅ | D3D11 compute via DXVK works | ✅ GPU3-only config |

## What's in this repo

| Directory | Contents |
|-----------|----------|
| `scripts/` | Launchers, patch tools, histogram watcher |
| `patches/` | `fix_createwindow.c`, Wine source patches, LD_PRELOAD alts |
| `patches/wine/` | `CreateDirect3D11DeviceFromDXGIDevice` + winewayland source patches |
| `docs/` | Root cause analysis (wl_surface + DXVK/vkd3d-proton) |
| `stubs/` | CC stub DLLs |

## Key Findings

- **GPU Pref Trick**: Start Lightroom with GPU=OFF in preferences. The launcher runs `gpu_pref_patcher.py off` before launch. CameraRaw startup GPU probe is broken; starting with GPU disabled skips it. Enabling GPU in Preferences triggers a working re-init path.
- **CreateDirect3D11DeviceFromDXGIDevice**: CameraRaw delay-imports this from d3d11.dll — not exported by DXVK or upstream Wine. Wine source patch at `patches/wine/0001-*`.
- **GPU2 vs GPU3**: GPU2 = D3D11 compute, GPU3 = D3D12 compute. GPU3-only is best X11 config.
- **Do NOT use d3d11 proxy**: HWND replacement breaks all rendering. Transparent pass-through only.

See [AGENTS.md](AGENTS.md) for full session knowledge base.

## Known Issues

- **Develop histogram**: DXVK + vkd3d-proton conflict on Pascal. No known fix — CPU fallback only.
- **Wayland**: Import freezes, previews gray (even with GPU trick — only histogram is fixed).
- **X11**: Develop flickers. `X_CopyArea` crash under XWayland (rare, restart fixes).
- **GPU toggle manual step**: After each launch, go to Preferences → Performance and toggle GPU ON. Workaround in development.

## AI Disclosure

Developed with assistance from opencode AI coding agent. Analysis, patches, and docs produced through iterative human-AI collaboration.

## License

MIT
