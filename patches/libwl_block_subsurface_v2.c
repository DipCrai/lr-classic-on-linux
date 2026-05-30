#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <unistd.h>
#include <stdlib.h>
#include <pthread.h>

/*
 * LD_PRELOAD: block wl_subsurface on surfaces that have VkSurface.
 *
 * Design:
 *  - Constructor: just print PID. NO dlsym/dlopen (unsafe at init time).
 *  - wl_display_connect (non-variadic entry point):
 *      Resolve ALL wayland symbols via dlsym(RTLD_NEXT) + dlopen fallback.
 *      Never fall back to RTLD_DEFAULT for wl_display_connect (avoids recursion).
 *  - wl_proxy_marshal_constructor_versioned (non-variadic, takes va_list):
 *      If real_ver not set, try dlsym(RTLD_DEFAULT) — no dlopen.
 *      Just forward (never consume va_list before forwarding).
 *  - wl_proxy_marshal_constructor (variadic):
 *      If real_ver not set, try dlsym(RTLD_DEFAULT) BEFORE va_start.
 *      Block get_subsurface, forward others.
 *  - NO wl_compositor_create_surface — it's a static inline, not exportable.
 *  - NO vkGetInstanceProcAddr — causes CreateDXGIFactory1 failure.
 */

/* =========== Types =========== */
struct wl_interface {
    const char *name;
    int version;
    int method_count;
    const void *methods;
    int event_count;
    const void *events;
};
struct wl_proxy {
    struct {
        const struct wl_interface *interface;
        const void *implementation;
        uint32_t id;
    } object;
    void *user_data;
    uint32_t version;
    uint32_t flags;
    int refcount;
    const void *queue;
};
struct wl_display;
struct wl_surface;

/* =========== State =========== */
static struct wl_proxy *(*real_ver)(struct wl_proxy *, uint32_t,
                                     const struct wl_interface *, va_list) = NULL;
static const struct wl_interface *wl_subcompositor_interface_ptr = NULL;

static volatile int resolved = 0;
static pthread_mutex_t res_lock = PTHREAD_MUTEX_INITIALIZER;

/* =========== Constructor =========== */
__attribute__((constructor))
static void init(void) {
    fprintf(stderr, "[wl_vk] Loaded (PID=%d)\n", getpid());
}

/* =========== Resolution — called from wl_display_connect only =========== */
static void resolve_all(void)
{
    if (resolved) return;
    pthread_mutex_lock(&res_lock);
    if (resolved) { pthread_mutex_unlock(&res_lock); return; }

    /* RTLD_NEXT skips our LD_PRELOAD library */
    real_ver = dlsym(RTLD_NEXT, "wl_proxy_marshal_constructor_versioned");

    if (!real_ver) {
        /* libwayland-client not loaded yet — force-load it */
        void *lib = dlopen("libwayland-client.so.0", RTLD_LAZY | RTLD_GLOBAL);
        if (lib) {
            real_ver = dlsym(lib, "wl_proxy_marshal_constructor_versioned");
            fprintf(stderr, "[wl_vk] Forced libwayland-client\n");
        }
    }

    wl_subcompositor_interface_ptr = dlsym(RTLD_DEFAULT,
                                            "wl_subcompositor_interface");
    /* Also pre-resolve our forwarder's real function from wl_display_connect */
    /* (resolved below in wl_display_connect) */

    resolved = (real_ver != NULL);
    fprintf(stderr, "[wl_vk] Resolve: ver=%p subcomp=%p ok=%d\n",
            (void*)real_ver, (void*)wl_subcompositor_interface_ptr, resolved);
    pthread_mutex_unlock(&res_lock);
}

/* =========== wl_display_connect — non-variadic entry point =========== */
struct wl_display *wl_display_connect(const char *name)
{
    /* Resolve everything on first call */
    if (!resolved) resolve_all();

    /* Get the REAL wl_display_connect — NEVER fall back to RTLD_DEFAULT
     * (which would find our own function — recursion!) */
    static struct wl_display *(*real_connect)(const char *);
    if (!real_connect) {
        real_connect = dlsym(RTLD_NEXT, "wl_display_connect");
        if (!real_connect && resolved) {
            /* real_ver was resolved via dlopen, so libwayland-client IS loaded.
             * Try RTLD_DEFAULT safely — it should NOT find us because
             * resolve_all loaded libwayland-client with RTLD_GLOBAL, and
             * wl_display_connect in libwayland-client should be found. */
            real_connect = dlsym(RTLD_DEFAULT, "wl_display_connect");
            /* But check for recursion: if RTLD_DEFAULT returns our address,
             * we have a problem. Detect by checking if it's a known address. */
            if (real_connect == wl_display_connect) {
                fprintf(stderr, "[wl_vk] FATAL: wl_display_connect recursion\n");
                real_connect = NULL;
            }
        }
    }

    if (real_connect) return real_connect(name);
    return NULL;
}

/* =========== wl_proxy_marshal_constructor_versioned (NOT variadic) =========== */
struct wl_proxy *
wl_proxy_marshal_constructor_versioned(struct wl_proxy *proxy, uint32_t opcode,
                                        const struct wl_interface *interface,
                                        va_list args)
{
    if (!real_ver) {
        real_ver = dlsym(RTLD_DEFAULT, "wl_proxy_marshal_constructor_versioned");
        if (!real_ver) return NULL;
    }
    return real_ver(proxy, opcode, interface, args);
}

/* =========== wl_proxy_marshal_constructor (variadic) =========== */
struct wl_proxy *
wl_proxy_marshal_constructor(struct wl_proxy *proxy, uint32_t opcode,
                              const struct wl_interface *interface, ...)
{
    va_list ap;

    if (!real_ver) {
        real_ver = dlsym(RTLD_DEFAULT, "wl_proxy_marshal_constructor_versioned");
        if (!real_ver) return NULL;
    }

    va_start(ap, interface);

    /* Block ALL get_subsurface unconditionally.
     * Surface comparison: interface pointer must match wl_subcompositor_interface. */
    if (interface && wl_subcompositor_interface_ptr &&
        interface == wl_subcompositor_interface_ptr) {
        fprintf(stderr, "[wl_vk] BLOCKED get_subsurface\n");
        va_end(ap);
        return NULL;
    }

    struct wl_proxy *ret = real_ver(proxy, opcode, interface, ap);
    va_end(ap);
    return ret;
}
