#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdarg.h>
#include <unistd.h>
#include <dlfcn.h>
#include <link.h>
#include <sys/mman.h>
#include <pthread.h>
#include <signal.h>

/* ================================================================
 * Interceptors for libwayland-client functions.
 * These are exported from our library and will be written into
 * winewayland.so's GOT entries.
 * ================================================================ */

/* Forward declarations with partial struct definition */
struct wl_proxy;
struct wl_interface {
    const char *name;
    int version;
    int method_count;
    const void *methods;
    int event_count;
    const void *events;
};

/* Intercept wl_proxy_marshal_constructor_versioned */
struct wl_proxy *wl_proxy_marshal_constructor_versioned(
    struct wl_proxy *proxy, uint32_t opcode,
    const struct wl_interface *interface,
    uint32_t version, va_list ap)
{
    static struct wl_proxy *(*real_func)(struct wl_proxy *, uint32_t,
                                          const struct wl_interface *,
                                          uint32_t, va_list) = NULL;
    if (!real_func) {
        real_func = dlsym(RTLD_NEXT, "wl_proxy_marshal_constructor_versioned");
    }

    /* Check if this is wl_subcompositor.get_subsurface.
     * The wl_subcompositor interface has opcode 1 for get_subsurface,
     * and the interface argument is wl_subsurface_interface.
     * We block if interface matches known subsurface types. */
    if (interface && strcmp(interface->name, "wl_subsurface") == 0) {
        fprintf(stderr, "[patch] BLOCKED get_subsurface (opcode=%u)\n", opcode);
        return NULL;
    }

    return real_func(proxy, opcode, interface, version, ap);
}

/* Intercept wl_proxy_marshal_constructor (variadic) */
struct wl_proxy *wl_proxy_marshal_constructor(
    struct wl_proxy *proxy, uint32_t opcode,
    const struct wl_interface *interface, ...)
{
    va_list ap;
    va_start(ap, interface);
    struct wl_proxy *ret = wl_proxy_marshal_constructor_versioned(
        proxy, opcode, interface, 0, ap);
    va_end(ap);
    return ret;
}

/* ================================================================
 * GOT patcher: scans loaded modules for winewayland.so and patches
 * its GOT entries for libwayland-client functions.
 * ================================================================ */

/* Target functions to intercept in winewayland.so's GOT */
static const char *target_funcs[] = {
    "wl_proxy_marshal_constructor_versioned",
    "wl_proxy_marshal_constructor",
    NULL
};

/* Number of target functions */
#define NUM_TARGETS 2

/* Structure for a GOT patch entry */
typedef struct {
    const char *name;
    void *our_addr;
    void *original_addr;
    int found;
} got_patch_entry_t;

static got_patch_entry_t patches[2];
static pthread_t monitor_thread;
static volatile int should_monitor = 0;

/* Read a file into a heap buffer */
static char *read_file(const char *path, size_t *out_len) {
    FILE *f = fopen(path, "r");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long len = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (len <= 0) { fclose(f); return NULL; }
    char *buf = malloc((size_t)len + 1);
    if (!buf) { fclose(f); return NULL; }
    size_t nread = fread(buf, 1, (size_t)len, f);
    fclose(f);
    buf[nread] = '\0';
    if (out_len) *out_len = nread;
    return buf;
}

/* Find the base address of a loaded library by scanning /proc/self/maps */
static unsigned long find_lib_base(const char *libname) {
    size_t len;
    char *maps = read_file("/proc/self/maps", &len);
    if (!maps) return 0;

    unsigned long base = 0;
    char *line = maps;
    char *nl;
    while ((nl = strchr(line, '\n')) != NULL) {
        *nl = '\0';
        if (strstr(line, libname)) {
            char *dash = strchr(line, '-');
            if (dash) {
                *dash = '\0';
                base = strtoul(line, NULL, 16);
                break;
            }
        }
        line = nl + 1;
    }
    free(maps);
    return base;
}

/* Helper: read memory from another loaded library's ELF headers via
 * direct pointer access (since we're in the same process, we can
 * just dereference pointers near the base address). */

/* Patch GOT entries in winewayland.so */
static void patch_got(unsigned long lib_base) {
    if (!lib_base) {
        fprintf(stderr, "[patch] No base address\n");
        return;
    }

    /* Verify it's an ELF */
    unsigned char *base = (unsigned char *)(uintptr_t)lib_base;
    if (base[0] != 0x7f || base[1] != 'E' || base[2] != 'L' || base[3] != 'F') {
        fprintf(stderr, "[patch] No ELF magic at %lx\n", lib_base);
        return;
    }

    /* Parse ELF header to find dynamic section */
    ElfW(Ehdr) *ehdr = (ElfW(Ehdr) *)base;
    ElfW(Phdr) *phdr = (ElfW(Phdr) *)(base + ehdr->e_phoff);
    ElfW(Dyn) *dynamic = NULL;

    /* Find PT_DYNAMIC */
    for (int i = 0; i < ehdr->e_phnum; i++) {
        if (phdr[i].p_type == PT_DYNAMIC) {
            dynamic = (ElfW(Dyn) *)(base + phdr[i].p_vaddr);
            break;
        }
    }
    if (!dynamic) {
        fprintf(stderr, "[patch] No PT_DYNAMIC\n");
        return;
    }

    /* Parse dynamic section */
    ElfW(Addr) strtab = 0;
    ElfW(Addr) symtab = 0;
    ElfW(Addr) jmprel = 0;
    ElfW(Xword) pltrelsz = 0;
    ElfW(Xword) pltreltype = 0;

    for (ElfW(Dyn) *d = dynamic; d->d_tag != DT_NULL; d++) {
        switch (d->d_tag) {
            case DT_STRTAB: strtab = d->d_un.d_ptr; break;
            case DT_SYMTAB: symtab = d->d_un.d_ptr; break;
            case DT_JMPREL: jmprel = d->d_un.d_ptr; break;
            case DT_PLTRELSZ: pltrelsz = d->d_un.d_val; break;
            case DT_PLTREL: pltreltype = d->d_un.d_val; break;
        }
    }

    if (!strtab || !symtab || !jmprel || !pltrelsz) {
        fprintf(stderr, "[patch] Incomplete dynamic info\n");
        return;
    }

    fprintf(stderr, "[patch] symtab=%lx strtab=%lx jmprel=%lx pltrelsz=%lu type=%lu\n",
            (unsigned long)symtab, (unsigned long)strtab,
            (unsigned long)jmprel, (unsigned long)pltrelsz,
            (unsigned long)pltreltype);

    /* Iterate PLT relocations */
    ElfW(Rela) *rela = NULL;
    ElfW(Rel) *rel = NULL;
    int nrel;

    if (pltreltype == DT_RELA) {
        rela = (ElfW(Rela) *)(base + jmprel);
        nrel = pltrelsz / sizeof(ElfW(Rela));
    } else {
        rel = (ElfW(Rel) *)(base + jmprel);
        nrel = pltrelsz / sizeof(ElfW(Rel));
    }

    ElfW(Sym) *syms = (ElfW(Sym) *)(base + symtab);
    char *strs = (char *)(base + strtab);

    int found_count = 0;

    for (int i = 0; i < nrel; i++) {
        ElfW(Addr) offset;
        ElfW(Xword) r_info;
        if (rela) {
            offset = rela[i].r_offset;
            r_info = rela[i].r_info;
        } else {
            offset = rel[i].r_offset;
            r_info = rel[i].r_info;
        }

        unsigned long sym_idx = r_info >> 32;
        unsigned long r_type = r_info & 0xffffffff;

        /* Only handle JUMP_SLOT relocations (x86_64: R_X86_64_JUMP_SLOT = 7) */
        if (r_type != 7) continue;

        char *sym_name = strs + syms[sym_idx].st_name;

        /* Check if this symbol is one of our targets */
        for (int t = 0; t < NUM_TARGETS; t++) {
            if (!patches[t].found && strcmp(sym_name, target_funcs[t]) == 0) {
                /* Found it. The GOT entry is at offset */
                ElfW(Addr) *got_entry = (ElfW(Addr) *)(uintptr_t)(lib_base + offset);

                /* Read current entry (resolved address from libwayland-client) */
                ElfW(Addr) current = *got_entry;
                patches[t].original_addr = (void *)current;

                /* Write our interceptor address */
                /* Note: GOT may be read-only if full RELRO is in effect.
                 * Use mprotect to make it writable first. */
                long page_size = sysconf(_SC_PAGESIZE);
                ElfW(Addr) page_start = (lib_base + offset) & ~(page_size - 1);
                if (mprotect((void *)page_start, page_size, PROT_READ | PROT_WRITE) != 0) {
                    fprintf(stderr, "[patch] mprotect failed for %lx: ", page_start);
                    perror("");
                    continue;
                }

                *got_entry = (ElfW(Addr))patches[t].our_addr;

                fprintf(stderr, "[patch] Patched %s: GOT+0x%lx (%p) %p -> %p\n",
                        sym_name, (unsigned long)offset,
                        (void *)got_entry,
                        (void *)current, patches[t].our_addr);
                patches[t].found = 1;
                found_count++;
                break;
            }
        }
    }

    fprintf(stderr, "[patch] Patched %d/%d targets\n", found_count, NUM_TARGETS);
}

/* Monitoring thread: periodically check for winewayland.so */
static void *monitor_thread_func(void *arg) {
    (void)arg;
    fprintf(stderr, "[patch] Monitor thread started\n");

    /* Resolve our own function addresses */
    for (int i = 0; i < NUM_TARGETS; i++) {
        patches[i].name = target_funcs[i];
        patches[i].our_addr = dlsym(RTLD_DEFAULT, target_funcs[i]);
        patches[i].found = 0;
        fprintf(stderr, "[patch] Target %s -> %p\n",
                target_funcs[i], patches[i].our_addr);
    }

    /* Poll for winewayland.so */
    for (int tries = 0; tries < 600; tries++) {  /* 60 seconds max */
        unsigned long base = find_lib_base("winewayland");
        if (base) {
            fprintf(stderr, "[patch] Found winewayland.so at 0x%lx\n", base);
            /* PLT already resolved (RTLD_NOW during load), patch immediately */
            patch_got(base);
            break;
        }
        usleep(50000);  /* Poll every 50ms */
    }

    fprintf(stderr, "[patch] Monitor thread done\n");
    should_monitor = 0;
    return NULL;
}

/* Constructor */
__attribute__((constructor))
static void init(void) {
    fprintf(stderr, "[patch] Loaded (PID=%d)\n", getpid());
    should_monitor = 1;
    pthread_create(&monitor_thread, NULL, monitor_thread_func, NULL);
}

/* Destructor */
__attribute__((destructor))
static void fini(void) {
    should_monitor = 0;
}
