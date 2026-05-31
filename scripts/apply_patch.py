#!/usr/bin/env python3
"""Apply ALL winewayland.so binary patches.

Patches:
  1. Subsurface reorder (0x12efe): Move set_client_surface before VkSurface creation
     to avoid wl_surface role conflict on NVIDIA.
  2. Visibility bypass (0x258be): Always take D3D path (skip GDI visibility block)
     so subsurface content is visible.

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

PATCHES = [
    {
        "name": "Subsurface reorder (0x12efe)",
        "offset": 0x12efe,
        "patch": bytes([
            0x48, 0x89, 0xde,           # mov %rbx,%rsi
            0x4c, 0x89, 0xe7,           # mov %r12,%rdi
            0xe8, 0x57, 0x29, 0x01, 0x00,  # call set_client_surface
            0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90,  # nop x10
        ]),
    },
    {
        "name": "Visibility bypass (0x258be)",
        "offset": 0x258be,
        "patch": bytes([0xeb]),  # jne (75) -> jmp (eb) — always skip visibility block
    },
]

def verify_patch(data, patch_info):
    off = patch_info["offset"]
    expected = patch_info["patch"]
    actual = bytes(data[off:off+len(expected)])
    return actual == expected, actual

def main():
    print("WARNING: Patches are build-specific (GE-Proton10-34).")
    print("Offsets and call distances may differ for other Proton versions.")
    print()

    if not os.path.exists(TARGET):
        print(f"ERROR: {TARGET} not found")
        print(f"Set PROTON_DIR to your GE-Proton installation directory")
        sys.exit(1)

    # Backup on first run
    if not os.path.exists(BACKUP):
        shutil.copy2(TARGET, BACKUP)
        print(f"Backup: {BACKUP}")
    else:
        print(f"Backup exists: {BACKUP}")

    with open(TARGET, "rb") as f:
        data = bytearray(f.read())

    all_ok = True
    for p in PATCHES:
        already, actual = verify_patch(data, p)
        if already:
            print(f"  ✓ {p['name']} — already applied")
            continue
        off = p["offset"]
        original = bytes(data[off:off+len(p["patch"])])
        print(f"  ~ {p['name']}")
        print(f"    Original: {original.hex()}")
        data[off:off+len(p["patch"])] = p["patch"]
        # Verify
        ok, actual = verify_patch(data, p)
        if ok:
            print(f"    Patched:  {actual.hex()} ✓")
        else:
            print(f"    FAILED:   {actual.hex()}")
            all_ok = False

    if not all_ok:
        print("\nERROR: One or more patches failed to apply. Restoring backup...")
        shutil.copy2(BACKUP, TARGET)
        sys.exit(1)

    with open(TARGET, "wb") as f:
        f.write(data)
    print(f"\nAll patches applied to {TARGET}")
    print("To revert: ./revert_patch.sh")

if __name__ == "__main__":
    main()
