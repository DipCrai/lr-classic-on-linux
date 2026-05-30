#!/usr/bin/env python3
"""Apply the winewayland.so binary patch (reorder subsurface before VkSurface).

Usage:
  ./apply_patch.py                    # Patch default Proton path
  PROTON_DIR=/path ./apply_patch.py   # Custom Proton path
"""
import os, sys, shutil

PROTON_DIR = os.environ.get("PROTON_DIR") or os.path.expanduser(
    "~/.steam/root/compatibilitytools.d/Proton-GE Latest"
)
TARGET = os.path.join(PROTON_DIR, "files/lib/wine/x86_64-unix/winewayland.so")
BACKUP = TARGET + ".backup"

# Offset in wayland_vulkan_surface_create, in bytes from file start
OFFSET = 0x12efe

# Patch bytes: mov rsi,rbx; mov rdi,r12; call set_client_surface; nop x10
PATCH = bytes([
    0x48, 0x89, 0xde,           # mov %rbx,%rsi
    0x4c, 0x89, 0xe7,           # mov %r12,%rdi
    0xe8, 0x57, 0x29, 0x01, 0x00,  # call set_client_surface (relative offset specific to this GE-Proton build)
    0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90,  # nop padding
])

def main():
    print("WARNING: This patch is build-specific (GE-Proton10-34).")
    print("For other Proton versions, the offset and call distance may differ.")
    print()
    
    if not os.path.exists(TARGET):
        print(f"ERROR: {TARGET} not found")
        print(f"Set PROTON_DIR to your GE-Proton installation directory")
        sys.exit(1)

    with open(TARGET, "rb") as f:
        data = bytearray(f.read())

    current = data[OFFSET:OFFSET+len(PATCH)]
    if current == PATCH:
        print(f"Patch already applied at 0x{OFFSET:x} — nothing to do.")
        return

    if not os.path.exists(BACKUP):
        shutil.copy2(TARGET, BACKUP)
        print(f"Backup: {BACKUP}")
    else:
        print(f"Backup exists: {BACKUP}")

    original = current
    print(f"Original at 0x{OFFSET:x}: {original.hex()}")

    data[OFFSET:OFFSET+len(PATCH)] = PATCH

    with open(TARGET, "wb") as f:
        f.write(data)

    # Verify patch was written correctly
    with open(TARGET, "rb") as f:
        data = bytearray(f.read())
    written = data[OFFSET:OFFSET+len(PATCH)]
    if written == PATCH:
        print(f"Patched {len(PATCH)} bytes at 0x{OFFSET:x}")
        print(f"Done. Verify: dd if={TARGET} bs=1 skip=$((0x{OFFSET:x})) count=6 2>/dev/null | xxd")
    else:
        print(f"ERROR: Patch verification failed at 0x{OFFSET:x}")
        print(f"Expected: {PATCH.hex()}")
        print(f"Got:      {written.hex()}")
        print("This may mean the original bytes at that offset don't match what this patch expects.")
        print("Restoring backup...")
        shutil.copy2(BACKUP, TARGET)
        sys.exit(1)

if __name__ == "__main__":
    main()
