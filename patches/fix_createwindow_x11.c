#include <windows.h>
#include <stdio.h>
#include <strsafe.h>

static BYTE trampoline_buf[32];
static BYTE original_bytes[12];
static void* trampoline = NULL;
static void* original_func = NULL;
static int debug = 0;

#define DBG(fmt, ...) do { \
    if (debug) { \
        char _buf[512]; \
        StringCbPrintfA(_buf, sizeof(_buf), "[fix_cw] " fmt "\n", ##__VA_ARGS__); \
        OutputDebugStringA(_buf); \
    } \
} while(0)

static int is_cef_class(LPCWSTR lpClassName) {
    if (!lpClassName) return 0;

    int len = lstrlenW(lpClassName);
    if (len == 0) return 0;

    /* Exact matches */
    if (lstrcmpiW(lpClassName, L"Chrome_WidgetWin_0") == 0) return 1;
    if (lstrcmpiW(lpClassName, L"Chrome_WidgetWin_1") == 0) return 1;
    if (lstrcmpiW(lpClassName, L"Chrome_RenderWidgetHostHWND") == 0) return 1;
    if (lstrcmpiW(lpClassName, L"Chrome_PluginsHWND") == 0) return 1;
    if (lstrcmpiW(lpClassName, L"CEF Browser") == 0) return 1;
    if (lstrcmpiW(lpClassName, L"CEF") == 0) return 1;

    /* Class starts with "Chrome_" */
    if (len >= 7) {
        if (CompareStringW(LOCALE_INVARIANT, NORM_IGNORECASE,
                           lpClassName, 7, L"Chrome_", 7) == CSTR_EQUAL) {
            return 1;
        }
    }

    /* Class ends with "Chrome_WidgetWin_0" or "Chrome_RenderWidgetHostHWND" */
    if (len >= 22) {
        LPCWSTR s = lpClassName + len - 22;
        if (lstrcmpiW(s, L"Chrome_WidgetWin_0") == 0 ||
            lstrcmpiW(s, L"Chrome_RenderWidgetHostHWND") == 0)
            return 1;
    }

    return 0;
}

static HWND WINAPI hook_CreateWindowExW(
    DWORD dwExStyle, LPCWSTR lpClassName, LPCWSTR lpWindowName,
    DWORD dwStyle, int X, int Y, int nWidth, int nHeight,
    HWND hWndParent, HMENU hMenu, HINSTANCE hInstance, LPVOID lpParam)
{
    DWORD origStyle = dwStyle;
    DWORD origExStyle = dwExStyle;

    if ((dwStyle & WS_CHILD) && is_cef_class(lpClassName)) {
        DBG("hooking class=%ls style=0x%08x ex=0x%08x parent=%p",
            lpClassName, dwStyle, dwExStyle, hWndParent);

        dwStyle &= ~WS_CHILD;
        dwStyle &= ~(WS_BORDER | WS_DLGFRAME | WS_THICKFRAME);
        dwStyle |= WS_POPUP;
        dwExStyle &= ~(WS_EX_CLIENTEDGE | WS_EX_STATICEDGE | WS_EX_MDICHILD);

        DBG("  -> new style=0x%08x ex=0x%08x", dwStyle, dwExStyle);
    }

    typedef HWND (WINAPI *Func)(DWORD,LPCWSTR,LPCWSTR,DWORD,int,int,int,int,HWND,HMENU,HINSTANCE,LPVOID);
    HWND hwnd = ((Func)trampoline)(dwExStyle, lpClassName, lpWindowName, dwStyle,
                                    X, Y, nWidth, nHeight, hWndParent, hMenu,
                                    hInstance, lpParam);

    if (origStyle != dwStyle && hwnd) {
        DBG("  result hwnd=%p", hwnd);
    }

    return hwnd;
}

static void install_hook(void) {
    HMODULE hUser32 = GetModuleHandleW(L"user32.dll");
    if (!hUser32) {
        DBG("cannot get user32");
        return;
    }

    original_func = (void*)GetProcAddress(hUser32, "CreateWindowExW");
    if (!original_func) {
        DBG("cannot find CreateWindowExW");
        return;
    }

    DWORD oldProtect;
    if (!VirtualProtect(original_func, 12, PAGE_EXECUTE_READWRITE, &oldProtect)) {
        DBG("VirtualProtect failed");
        return;
    }

    memcpy(original_bytes, original_func, 12);

    BYTE jmp_code[] = {
        0x48, 0xB8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0xFF, 0xE0
    };
    void* hook_addr = hook_CreateWindowExW;
    memcpy(&jmp_code[2], &hook_addr, 8);
    memcpy(original_func, jmp_code, 12);

    trampoline = VirtualAlloc(NULL, 32, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    if (!trampoline) {
        memcpy(original_func, original_bytes, 12);
        VirtualProtect(original_func, 12, oldProtect, &oldProtect);
        DBG("trampoline alloc failed");
        return;
    }

    memcpy(trampoline, original_bytes, 12);
    BYTE back_jmp[] = {
        0x48, 0xB8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0xFF, 0xE0
    };
    void* return_addr = (BYTE*)original_func + 12;
    memcpy(&back_jmp[2], &return_addr, 8);
    memcpy((BYTE*)trampoline + 12, back_jmp, 12);

    VirtualProtect(original_func, 12, oldProtect, &oldProtect);
    FlushInstructionCache(GetCurrentProcess(), original_func, 12);
    FlushInstructionCache(GetCurrentProcess(), trampoline, 24);

    DBG("hook installed");
}

static void remove_hook(void) {
    if (!original_func) return;
    DWORD oldProtect;
    if (VirtualProtect(original_func, 12, PAGE_EXECUTE_READWRITE, &oldProtect)) {
        memcpy(original_func, original_bytes, 12);
        VirtualProtect(original_func, 12, oldProtect, &oldProtect);
        FlushInstructionCache(GetCurrentProcess(), original_func, 12);
    }
    if (trampoline) {
        VirtualFree(trampoline, 0, MEM_RELEASE);
        trampoline = NULL;
    }
}

BOOL WINAPI DllMain(HINSTANCE hinstDLL, DWORD fdwReason, LPVOID lpvReserved) {
    (void)hinstDLL;
    if (fdwReason == DLL_PROCESS_ATTACH) {
        debug = (GetEnvironmentVariableA("FIX_CW_DEBUG", NULL, 0) > 0);
        DisableThreadLibraryCalls(hinstDLL);
        install_hook();
    } else if (fdwReason == DLL_PROCESS_DETACH) {
        if (!lpvReserved) remove_hook();
    }
    return TRUE;
}

__declspec(dllexport) void WINAPI fix_createwindow(void) {
}