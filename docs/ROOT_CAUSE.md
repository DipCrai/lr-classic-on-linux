# Root Cause Analysis

## wl_surface Role Conflict (the main bug)

### The Problem

`winewayland.drv` creates a D3D11/Vulkan surface for each child HWND in a Wayland session. The child HWND's rendering goes through DXVK → Vulkan swapchain, which requires a `wl_surface` (Wayland primitive). `winewayland.drv` also makes child windows into `wl_subsurface`s of their parent, to support proper window positioning and clipping.

The conflict: **both roles are assigned to the SAME `wl_surface`**.

### The Call Chain

```
Application (Lightroom)
  ↓ D3D11CreateDeviceAndSwapChain(hwnd=CHILD)
DXVK (d3d11.dll → dxgi.dll)
  ↓ vkCreateWin32SurfaceKHR(hwnd)  [Win32 → Wayland translation]
winewayland.drv
  ↓ wayland_vulkan_surface_create(hwnd)
  1. wayland_client_surface_create(hwnd)
     → wl_compositor_create_surface()  →  creates wl_surface_A (NO ROLE)
  2. vkCreateWaylandSurfaceKHR(display, ..., wl_surface_A, ...)
     → wl_surface_A gets "VkSurface" role implicitly
  3. set_client_surface(hwnd, client_surface)
     → wayland_client_surface_attach(...)
       → wl_subcompositor.get_subsurface(wl_surface_A, parent_surface)
         → wl_surface_A gets "wl_subsurface" role
         → **ROLE CONFLICT** — surface already has VkSurface role!
NVIDIA Wayland Driver
  ↓ vkCreateSwapchainKHR(...)
  → REJECTED: "wl_surface already has a role"
DXVK
  ↓ Hangs waiting for swapchain
```

### Why It Only Affects Wayland

On X11, child windows are real X11 windows with their own XID. DXVK creates XCB Vulkan surfaces from X11 windows. There is no "subsurface" concept — child windows just have a different visual/offset. The X11 model maps directly to child HWNDs.

On Wayland, `winewayland.drv` uses `wl_subsurface` to emulate child windows. But the Vulkan surface needs a `wl_surface` too, and Wayland protocol disallows multiple roles.

### Why NVIDIA Specifically?

The Wayland protocol says a wl_surface can have only one role. However, the Mesa driver (used by AMD/Intel GPUs) does not strictly enforce this — it allows creating a swapchain on a wl_surface even after assigning a subsurface role. The NVIDIA driver enforces the protocol correctly and rejects the swapchain.

This means the bug exists on all GPUs, but only manifests crashing/hanging on NVIDIA.

### The Fix: Two Options

#### Option A: Reorder (simpler)

Move `set_client_surface()` before `vkCreateWaylandSurfaceKHR()`. The wl_surface gets the subsurface role first, then the VkSurface role is added. The NVIDIA driver accepts this because the role set doesn't change after VkSurface creation:

```
Before (broken):   create_surface → VkSurface → attach[subsurface]  → swapchain ✗
After  (fixed):    create_surface → attach[subsurface] → VkSurface  → swapchain ✓
```

**Trade-off**: The subsurface role is assigned to ALL wl_surfaces, even those that won't get a VkSurface. But this is harmless — the subsurface is simply unused for non-Vulkan surfaces.

#### Option B: Separate wl_surfaces (cleaner)

Create TWO wl_surfaces per HWND:
- One for the subsurface role (GDI/software rendering)
- One for the VkSurface (Vulkan/D3D11 rendering)

This is the architecturally correct fix but requires more code changes.

### Why LD_PRELOAD Doesn't Work

The intercept approach (LD_PRELOAD to block `wl_subcompositor.get_subsurface`) has two problems:

1. **RTLD_LOCAL issue**: Wine loads `winewayland.so` via `dlopen(path, RTLD_NOW)`. With `RTLD_LOCAL` (default), PLT resolution searches the loaded library's DT_NEEDED dependencies before the global scope. LD_PRELOAD interceptors are in the global scope, so they're never reached for functions resolved through PLT within the RTLD_LOCAL group.

2. **Invisible content**: Even if the subsurface is blocked (preventing the role conflict), the wl_surface has NO role at all. The Wayland compositor ignores buffers committed to role-less surfaces, so content is invisible.

## X11 Flickering

NVIDIA driver 580.159.03 has a bug where both Vulkan Present (`VK_PRESENT_MODE_FIFO_KHR`) and GLX Present (`GLX_EXT_swap_control`) bypass vsync. This causes screen tearing regardless of swap interval setting.

The issue is in the driver's presentation path — it's not something userspace can work around. The only fix is to use Wayland (which uses a different presentation mechanism via the Wayland protocol's `wl_surface.frame` callbacks).

## CEF Import Dialog

### Why It's Broken

CEF (Chromium Embedded Framework) creates child windows (`WS_CHILD`) for its web content. On Wayland:

1. `winewayland.drv` makes child windows into `wl_subsurface`s
2. CEF renders via D3D11 → DXVK → Vulkan
3. The subsurface's wl_surface gets the role conflict (same as Issue 1)
4. Additionally, CEF content on subsurfaces has visibility/positioning issues

### The fix_createwindow.dll Workaround

By converting CEF's `WS_CHILD` windows to `WS_POPUP` (top-level), each CEF window gets its own `xdg_toplevel` role separate from the parent. This avoids both the subsurface rendering issues and the role conflict.

### Why --disable-gpu Breaks It

`--disable-gpu` makes CEF use software rendering (GDI via `wl_shm` buffer). On Wayland with winewayland.drv, this means:
1. GDI content is rendered to the wl_subsurface
2. The wl_subsurface is attached to the parent's xdg_toplevel
3. The parent xdg_toplevel may cover the subsurface
4. Result: white/invisible CEF window

With `--in-process-gpu` (the correct flag):
1. CEF uses ANGLE → D3D11 → DXVK → Vulkan
2. The Vulkan swapchain creates its own presentation surface
3. With fix_createwindow, this surface is on a separate xdg_toplevel
4. Result: visible, interactive CEF window

## Other Findings

### wl_proxy_marshal ABI Details

`wl_proxy_marshal_constructor` is variadic. On x86_64 (System V AMD64 ABI), variadic functions pass the first 6 integer args in registers, and additional args on the stack. The `va_list` type refers to a register save area. Forwarding a variadic call by passing `va_list` through a non-variadic intermediate corrupts this — the intermediate function's prologue does not set up the register save area.

The correct approach: only intercept the non-variadic `wl_proxy_marshal_constructor_versioned` (which takes `va_list` explicitly), and have the variadic `wl_proxy_marshal_constructor` use `va_start`/`va_end` to call the versioned variant.

### dlsym(RTLD_NEXT) in Interceptors

Calling `dlsym(RTLD_NEXT, ...)` from within a variadic interceptor corrupts the register save area because `dlsym` is not transparent to variadic argument passing. All function pointer resolution for interceptors must happen in `__attribute__((constructor))`, never in the interceptor body.

### GOT/Patching via /proc/self/mem

An alternative approach that works despite RTLD_LOCAL: use a monitoring thread that scans `/proc/self/maps` for `winewayland.so`, then patches its GOT entries via `/proc/self/mem` or direct memory writes with `mprotect`. This is demonstrated in `patches/libwl_got_patch.c`.
