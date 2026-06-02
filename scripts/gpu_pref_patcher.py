#!/usr/bin/env python3
"""Patch Lightroom agprefs to set GPU state before launch."""
import sys, os, re

WINEPREFIX = os.environ.get('WINEPREFIX', os.path.expanduser('~/.lightroom_prefix/pfx'))
PREF_FILE = os.path.join(
    WINEPREFIX,
    "drive_c/users/steamuser/AppData/Roaming/Adobe/Lightroom/Preferences"
    "/Lightroom Classic CC 7 Preferences.agprefs"
)

GPU_OFF = {
    'GPUManagerPref': '"off"',
    'useGPUCompute': 'false',
    'useGPUForExport': 'false',
    'useGPUForPreviews': '"off"',
    'useGPUInLibrary': 'false',
    'customGPUCPref': 'false',
    'customGPUDPref': 'false',
    'isGPU3EnabledOnDevice': 'false',
    'isLCOnGPU3': 'false',
    'statusGPUPreviewsKey': 'false',
}

GPU_ON = {
    'GPUManagerPref': '"auto"',
    'useGPUCompute': 'true',
    'useGPUForExport': 'true',
    'useGPUForPreviews': '"auto"',
    'useGPUInLibrary': 'false',
    'customGPUCPref': 'false',
    'customGPUDPref': 'false',
    'isGPU3EnabledOnDevice': 'false',
    'isLCOnGPU3': 'true',
    'statusGPUPreviewsKey': 'false',
}

def patch(state: str):
    if state == 'off':
        settings = GPU_OFF
    elif state == 'on':
        settings = GPU_ON
    else:
        print(f"Usage: {sys.argv[0]} off|on")
        sys.exit(1)

    if not os.path.exists(PREF_FILE):
        print(f"Pref file not found: {PREF_FILE}")
        sys.exit(1)

    with open(PREF_FILE, 'rb') as f:
        data = f.read()

    text = data.decode('utf-8', errors='replace')

    for key, val in settings.items():
        m = re.search(rf'\t{key} = .*,', text)
        if m:
            old = m.group(0)
            new = f'\t{key} = {val},'
            text = text.replace(old, new, 1)
            print(f"  {old.strip()} → {new.strip()}")

    with open(PREF_FILE, 'wb') as f:
        f.write(text.encode('utf-8'))

    print(f"GPU state set to '{state}'")

if __name__ == '__main__':
    if len(sys.argv) != 2 or sys.argv[1] not in ('off', 'on'):
        print(f"Usage: {sys.argv[0]} off|on")
        sys.exit(1)
    patch(sys.argv[1])
