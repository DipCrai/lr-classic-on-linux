#!/usr/bin/env python3
"""Apply the winewayland.so binary patch (reorder subsurface before VkSurface)."""

import os, sys, shutil

PROTON_DIR = os.path.expanduser("~/.steam/root/compatibilitytools.d/Proton-GE Latest")
TARGET = os.path.join(PROTON_DIR, "files/lib/wine/x86_64-unix/winewayland.so")
BACKUP = TARGET + ".backup"

# Offset in wayland_vulkan_surface_create, in bytes from file start
OFFSET = 0x12efe

# Patch bytes: mov rsi,rbx; mov rdi,r12; call set_client_surface; nop x10
PATCH = bytes([
    0x48, 0x89, 0xde,           # mov %rbx,%rsi
    0x4c, 0x89, 0xe7,           # mov %r12,%rdi
    0xe8, 0x57, 0x29, 0x01, 0x00,  # call set_client_surface (relative offset in Proton)
    0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90,  # nop padding
])

def main():
    if not os.path.exists(TARGET):
        print(f"ERROR: {TARGET} not found")
        sys.exit(1)

    # Backup
    if not os.path.exists(BACKUP):
        shutil.copy2(TARGET, BACKUP)
        print(f"Backup saved to {BACKUP}")
    else:
        print(f"Backup exists at {BACKUP}")

    # Read, patch, write
    with open(TARGET, "rb") as f:
        data = bytearray(f.read())

    # Verify original bytes (NtUserCallHwndParam pattern)
    original = data[OFFSET:OFFSET+len(PATCH)]
    print(f"Original bytes at 0x{OFFSET:x}: {original.hex()}")

    # Apply patch
    data[OFFSET:OFFSET+len(PATCH)] = PATCH

    with open(TARGET, "wb") as f:
        f.write(data)

    print(f"Patched {len(PATCH)} bytes at offset 0x{OFFSET:x}")
    print("Done! winewayland.so patched successfully.")

if __name__ == "__main__":
    main()
