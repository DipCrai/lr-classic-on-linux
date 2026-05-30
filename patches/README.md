# Patches

## winewayland.drv — reorder subsurface creation

### Binary patch

The binary patch modifies `winewayland.so` at offset `0x12efe` in `wayland_vulkan_surface_create`:

**Original** (21 bytes at 0x12efe):
```
NtUserCallHwndParam + test/jne → D3D vs GDI check (branch)
```

**Patched**:
```
mov %rbx,%rsi     ; rsi = client
mov %r12,%rdi     ; rdi = hwnd
call set_client_surface
nop × 10
```

This moves `set_client_surface` before `vkCreateWaylandSurfaceKHR`.

### Source patch

```diff
--- a/dlls/winewayland.drv/vulkan.c
+++ b/dlls/winewayland.drv/vulkan.c
@@ -XXX,XX +XXX,XX @@ static HWND wayland_vulkan_surface_create(HWND hwnd)
     if (!client_surface)
         return NULL;

+    /* Attach client surface BEFORE creating VkSurface to avoid
+     * wl_surface role conflict (VkSurface + wl_subsurface on same surface).
+     * NVIDIA Wayland driver rejects surfaces whose role changes after
+     * VkSurface creation. */
+    set_client_surface(hwnd, client_surface);
+
     surface = wayland_surface_create(display, client, hwnd, FALSE);
     if (!surface)
     {
         wayland_client_surface_destroy(client_surface);
         return NULL;
     }
-
-    set_client_surface(hwnd, client_surface);
```

## fix_createwindow.dll — CEF child → popup conversion

Source: `fix_createwindow.c`

An AppInit DLL that intercepts `CreateWindowExW` in `user32.dll` and converts CEF child windows from `WS_CHILD` to `WS_POPUP` + `WS_EX_APPWINDOW`.

**Build**:
```bash
x86_64-w64-mingw32-gcc -shared -O2 -s -o fix_createwindow.dll fix_createwindow.c
```

**Register**:
```bash
cp fix_createwindow.dll "$WINEPREFIX/drive_c/windows/system32/"
wine64 reg add "HKLM\Software\Microsoft\Windows NT\CurrentVersion\Windows" /v "AppInit_DLLs" /t REG_SZ /d "C:\windows\system32\fix_createwindow.dll" /f
wine64 reg add "HKLM\Software\Microsoft\Windows NT\CurrentVersion\Windows" /v "LoadAppInit_DLLs" /t REG_DWORD /d 1 /f
```

### X11 vs Wayland variant

**Wayland (recommended)**: Use `fix_createwindow.c` as-is. Keeps window frames (`WS_BORDER`, `WS_DLGFRAME`, `WS_THICKFRAME`), adds `WS_EX_APPWINDOW`. CEF windows render correctly on Wayland subsurfaces.

**X11**: Strip frame styles for import dialog to render correctly. Add these lines after `dwStyle &= ~WS_CHILD`:
```c
dwStyle &= ~(WS_BORDER | WS_DLGFRAME | WS_THICKFRAME);
dwExStyle &= ~(WS_EX_CLIENTEDGE | WS_EX_STATICEDGE | WS_EX_MDICHILD);
```
See `patches/fix_createwindow_x11.c` for the full X11 version.

## LD_PRELOAD libraries (for reference)

- `libwl_got_patch.c` — GOT-patching via monitoring thread (avoids RTLD_LOCAL issue)
- `libwl_block_subsurface_v2.c` — Direct LD_PRELOAD (doesn't work with RTLD_LOCAL)

These are included for developers who want to experiment with alternative approaches.
