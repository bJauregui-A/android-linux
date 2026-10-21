#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <unistd.h>

#define UDMABUF_DEV makedev(10, 123)
#define UDMABUF_CREATE 0x40187542UL

struct udmabuf_create {
    uint32_t memfd;
    uint32_t flags;
    uint64_t offset;
    uint64_t size;
};

struct dma_heap_allocation_data {
    uint64_t len;
    uint32_t fd;
    uint32_t fd_flags;
    uint64_t heap_flags;
};

#define DMA_HEAP_IOCTL_ALLOC _IOWR('H', 0x0, struct dma_heap_allocation_data)

/* Respaldo por KGSL si SELinux bloquea /dev/dma_heap/system en apps:
   reserva memoria GPU exportable como dma_buf en /dev/kgsl-3d0.  */
struct kgsl_gpumem_alloc_id {
    unsigned int id;
    unsigned int flags;
    size_t size;
    size_t mmapsize;
    uint64_t gpuaddr;
    uint64_t __pad;
    uint64_t __pad2;
};

struct kgsl_gpumem_free_id {
    unsigned int id;
    unsigned int __pad;
};

struct kgsl_gpumem_export_dmabuf {
    unsigned int id;
    int fd;
};

#define IOCTL_KGSL_GPUMEM_ALLOC_ID _IOWR(0x09, 0x34, struct kgsl_gpumem_alloc_id)
#define IOCTL_KGSL_GPUMEM_FREE_ID _IOWR(0x09, 0x35, struct kgsl_gpumem_free_id)
#define IOCTL_KGSL_GPUMEM_EXPORT_DMABUF _IOWR(0x09, 0x3c, struct kgsl_gpumem_export_dmabuf)
#define KGSL_MEMFLAGS_USE_CPU_MAP 0x10000000U
#define KGSL_CACHEMODE_WRITEBACK (3U << 26)

static int (* obtener_real_open(void))(const char *, int, mode_t) {
    static int (*fn)(const char *, int, mode_t);
    if (!fn) fn = dlsym(RTLD_NEXT, "open");
    return fn;
}

static int (* obtener_real_ioctl(void))(int, unsigned long, void *) {
    static int (*fn)(int, unsigned long, void *);
    if (!fn) fn = dlsym(RTLD_NEXT, "ioctl");
    return fn;
}

static void *(* obtener_real_mmap(void))(void *, size_t, int, int, int, off_t) {
    static void *(*fn)(void *, size_t, int, int, int, off_t);
    if (!fn) fn = dlsym(RTLD_NEXT, "mmap");
    return fn;
}

static int reservar_dmabuf_real(uint64_t size, int (*real_open)(const char *, int, mode_t),
                                int (*real_ioctl)(int, unsigned long, void *)) {
    static int heap_fd = -2;
    if (heap_fd == -2) {
        heap_fd = real_open("/dev/dma_heap/system", O_RDONLY | O_CLOEXEC, 0);
    }
    if (heap_fd >= 0) {
        struct dma_heap_allocation_data alloc = {
            .len = size,
            .fd = 0,
            .fd_flags = O_RDWR | O_CLOEXEC,
            .heap_flags = 0,
        };
        if (real_ioctl(heap_fd, DMA_HEAP_IOCTL_ALLOC, &alloc) == 0 && (int)alloc.fd >= 0) {
            return (int)alloc.fd;
        }
    }
    static int kgsl_fd = -2;
    if (kgsl_fd == -2) {
        kgsl_fd = real_open("/dev/kgsl-3d0", O_RDWR | O_CLOEXEC, 0);
    }
    if (kgsl_fd >= 0) {
        struct kgsl_gpumem_alloc_id alloc = {
            .flags = KGSL_MEMFLAGS_USE_CPU_MAP | KGSL_CACHEMODE_WRITEBACK,
            .size = size,
        };
        if (real_ioctl(kgsl_fd, IOCTL_KGSL_GPUMEM_ALLOC_ID, &alloc) == 0) {
            struct kgsl_gpumem_export_dmabuf exp = {
                .id = alloc.id,
                .fd = -1,
            };
            int ok = (real_ioctl(kgsl_fd, IOCTL_KGSL_GPUMEM_EXPORT_DMABUF, &exp) == 0 && exp.fd >= 0);
            struct kgsl_gpumem_free_id free_req = { .id = alloc.id };
            real_ioctl(kgsl_fd, IOCTL_KGSL_GPUMEM_FREE_ID, &free_req);
            if (ok) {
                return exp.fd;
            }
        }
    }
    return -1;
}

static int es_udmabuf_fd(int fd) {
    char path[64], target[128];
    if (fd < 0) return 0;
    snprintf(path, sizeof(path), "/proc/self/fd/%d", fd);
    ssize_t n = readlink(path, target, sizeof(target) - 1);
    if (n <= 0) return 0;
    target[n] = '\0';
    return strstr(target, "memfd:udmabuf-dev") != NULL;
}

static int es_ruta_emulada(const char *pathname) {
    if (!pathname) return 0;
    return strcmp(pathname, "/dev/udmabuf") == 0 ||
           strcmp(pathname, "/dev/dri/renderD128") == 0 ||
           strcmp(pathname, "/dev/dri/card0") == 0;
}

static int abrir_udmabuf(int flags) {
    (void)flags;
    return memfd_create("udmabuf-dev", MFD_CLOEXEC);
}

int open(const char *pathname, int flags, ...) {
    int (*real_open)(const char *, int, mode_t) = obtener_real_open();
    if (es_ruta_emulada(pathname))
        return abrir_udmabuf(flags);
    mode_t mode = 0;
    if (flags & (O_CREAT | O_TMPFILE)) {
        va_list ap;
        va_start(ap, flags);
        mode = va_arg(ap, mode_t);
        va_end(ap);
    }
    return real_open(pathname, flags, mode);
}

int open64(const char *pathname, int flags, ...) {
    static int (*real_open64)(const char *, int, mode_t);
    if (!real_open64) real_open64 = dlsym(RTLD_NEXT, "open64");
    if (es_ruta_emulada(pathname))
        return abrir_udmabuf(flags);
    mode_t mode = 0;
    if (flags & (O_CREAT | O_TMPFILE)) {
        va_list ap;
        va_start(ap, flags);
        mode = va_arg(ap, mode_t);
        va_end(ap);
    }
    return real_open64(pathname, flags, mode);
}

int openat(int dirfd, const char *pathname, int flags, ...) {
    static int (*real_openat)(int, const char *, int, mode_t);
    if (!real_openat) real_openat = dlsym(RTLD_NEXT, "openat");
    if (es_ruta_emulada(pathname))
        return abrir_udmabuf(flags);
    mode_t mode = 0;
    if (flags & (O_CREAT | O_TMPFILE)) {
        va_list ap;
        va_start(ap, flags);
        mode = va_arg(ap, mode_t);
        va_end(ap);
    }
    return real_openat(dirfd, pathname, flags, mode);
}

int openat64(int dirfd, const char *pathname, int flags, ...) {
    static int (*real_openat64)(int, const char *, int, mode_t);
    if (!real_openat64) real_openat64 = dlsym(RTLD_NEXT, "openat64");
    if (es_ruta_emulada(pathname))
        return abrir_udmabuf(flags);
    mode_t mode = 0;
    if (flags & (O_CREAT | O_TMPFILE)) {
        va_list ap;
        va_start(ap, flags);
        mode = va_arg(ap, mode_t);
        va_end(ap);
    }
    return real_openat64(dirfd, pathname, flags, mode);
}

int fstat(int fd, struct stat *st) {
    static int (*real_fstat)(int, struct stat *);
    if (!real_fstat) real_fstat = dlsym(RTLD_NEXT, "fstat");
    int r = real_fstat(fd, st);
    if (r == 0 && es_udmabuf_fd(fd)) {
        st->st_mode = (st->st_mode & ~S_IFMT) | S_IFCHR;
        st->st_rdev = UDMABUF_DEV;
    }
    return r;
}

int fstat64(int fd, struct stat64 *st) {
    return fstat(fd, (struct stat *)st);
}

static __thread int tls_mmap_fd = -1;
static __thread void *tls_mmap_addr = NULL;
static __thread size_t tls_mmap_len = 0;

void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset) {
    void *(*real_mmap)(void *, size_t, int, int, int, off_t) = obtener_real_mmap();
    void *res = real_mmap(addr, length, prot, flags, fd, offset);
    if (res != MAP_FAILED && fd >= 0 && offset == 0 && (flags & MAP_SHARED)) {
        tls_mmap_fd = fd;
        tls_mmap_addr = res;
        tls_mmap_len = length;
    }
    return res;
}

void *mmap64(void *addr, size_t length, int prot, int flags, int fd, off64_t offset) {
    return mmap(addr, length, prot, flags, fd, (off_t)offset);
}

int ioctl(int fd, unsigned long req, ...) {
    int (*real_ioctl)(int, unsigned long, void *) = obtener_real_ioctl();
    int (*real_open)(const char *, int, mode_t) = obtener_real_open();
    void *(*real_mmap)(void *, size_t, int, int, int, off_t) = obtener_real_mmap();
    va_list ap;
    va_start(ap, req);
    void *arg = va_arg(ap, void *);
    va_end(ap);
    if (req == UDMABUF_CREATE && es_udmabuf_fd(fd) && arg != NULL) {
        struct udmabuf_create *c = (struct udmabuf_create *)arg;
        int dmabuf_fd = reservar_dmabuf_real(c->size, real_open, real_ioctl);
        if (dmabuf_fd >= 0) {
            if (tls_mmap_fd == (int)c->memfd && tls_mmap_addr != NULL && tls_mmap_len == c->size) {
                real_mmap(tls_mmap_addr, tls_mmap_len,
                          PROT_READ | PROT_WRITE, MAP_SHARED | MAP_FIXED,
                          dmabuf_fd, 0);
                tls_mmap_fd = -1;
                tls_mmap_addr = NULL;
                tls_mmap_len = 0;
            }
            return dmabuf_fd;
        }
        return fcntl(c->memfd, F_DUPFD_CLOEXEC, 0);
    }
    return real_ioctl(fd, req, arg);
}

/* ---------- Emulación libdrm + libgbm + EGLDevice para Aquamarine / Hyprland ---------- */

#define DRM_NODE_PRIMARY 0
#define DRM_NODE_CONTROL 1
#define DRM_NODE_RENDER  2
#define DRM_NODE_MAX     3

typedef struct _drmDevice {
    char **nodes;
    int available_nodes;
    int bustype;
    void *businfo;
    void *deviceinfo;
} drmDevice, *drmDevicePtr;

static int crear_drm_device_falso(drmDevicePtr *device) {
    if (!device) return -EINVAL;
    drmDevicePtr d = calloc(1, sizeof(drmDevice));
    if (!d) return -ENOMEM;
    d->nodes = calloc(DRM_NODE_MAX, sizeof(char *));
    if (!d->nodes) {
        free(d);
        return -ENOMEM;
    }
    d->nodes[DRM_NODE_PRIMARY] = strdup("/dev/dri/card0");
    d->nodes[DRM_NODE_RENDER]  = strdup("/dev/dri/renderD128");
    d->available_nodes = (1 << DRM_NODE_PRIMARY) | (1 << DRM_NODE_RENDER);
    *device = d;
    return 0;
}

int drmGetDeviceFromDevId(dev_t dev_id, uint32_t flags, drmDevicePtr *device) {
    (void)dev_id; (void)flags;
    return crear_drm_device_falso(device);
}

int drmGetDevice2(int fd, uint32_t flags, drmDevicePtr *device) {
    (void)fd; (void)flags;
    return crear_drm_device_falso(device);
}

int drmGetDevice(int fd, drmDevicePtr *device) {
    return drmGetDevice2(fd, 0, device);
}

void drmFreeDevice(drmDevicePtr *device) {
    if (!device || !*device) return;
    drmDevicePtr d = *device;
    if (d->nodes) {
        for (int i = 0; i < DRM_NODE_MAX; i++) free(d->nodes[i]);
        free(d->nodes);
    }
    free(d);
    *device = NULL;
}

int drmDevicesEqual(drmDevicePtr a, drmDevicePtr b) {
    return (a != NULL && b != NULL) ? 1 : 0;
}

int drmIsMaster(int fd) {
    (void)fd;
    return 0;
}

int drmGetNodeTypeFromFd(int fd) {
    (void)fd;
    return DRM_NODE_RENDER;
}

char *drmGetRenderDeviceNameFromFd(int fd) {
    (void)fd;
    return strdup("/dev/dri/renderD128");
}

char *drmGetPrimaryDeviceNameFromFd(int fd) {
    (void)fd;
    return strdup("/dev/dri/card0");
}

char *drmGetDeviceNameFromFd2(int fd) {
    (void)fd;
    return strdup("/dev/dri/renderD128");
}

int drmGetCap(int fd, uint64_t capability, uint64_t *value) {
    (void)fd;
    if (capability == 0x5 /* DRM_CAP_PRIME */ && value) {
        *value = 0x1 | 0x2; /* DRM_PRIME_CAP_IMPORT | DRM_PRIME_CAP_EXPORT */
        return 0;
    }
    return -EOPNOTSUPP;
}

int drmPrimeFDToHandle(int fd, int prime_fd, uint32_t *handle) {
    (void)fd; (void)prime_fd;
    if (handle) *handle = 1;
    return 0;
}

int drmCloseBufferHandle(int fd, uint32_t handle) {
    (void)fd; (void)handle;
    return 0;
}

void *drmGetVersion(int fd) {
    (void)fd;
    return NULL;
}

struct gbm_device {
    int fd;
};

struct gbm_bo {
    struct gbm_device *gbm;
    uint32_t width;
    uint32_t height;
    uint32_t stride;
    uint32_t format;
    uint64_t modifier;
    int dmabuf_fd;
    void *user_data;
    void (*destroy_user_data)(struct gbm_bo *, void *);
};

struct gbm_device *gbm_create_device(int fd) {
    struct gbm_device *gbm = calloc(1, sizeof(*gbm));
    if (!gbm) return NULL;
    gbm->fd = fd;
    return gbm;
}

void gbm_device_destroy(struct gbm_device *gbm) {
    free(gbm);
}

int gbm_device_get_fd(struct gbm_device *gbm) {
    return gbm ? gbm->fd : -1;
}

const char *gbm_device_get_backend_name(struct gbm_device *gbm) {
    (void)gbm;
    return "drm";
}

int gbm_device_is_format_supported(struct gbm_device *gbm, uint32_t format, uint32_t usage) {
    (void)gbm; (void)format; (void)usage;
    return 1;
}

int gbm_device_get_format_modifier_plane_count(struct gbm_device *gbm, uint32_t format, uint64_t modifier) {
    (void)gbm; (void)format; (void)modifier;
    return 1;
}

struct gbm_bo *gbm_bo_create(struct gbm_device *gbm, uint32_t width, uint32_t height,
                             uint32_t format, uint32_t flags) {
    (void)flags;
    if (!gbm || width == 0 || height == 0) return NULL;
    uint32_t stride = ((width * 4U) + 255U) & ~255U;
    uint64_t size = (uint64_t)stride * (uint64_t)height;
    int dmabuf_fd = reservar_dmabuf_real(size, obtener_real_open(), obtener_real_ioctl());
    if (dmabuf_fd < 0) return NULL;
    struct gbm_bo *bo = calloc(1, sizeof(*bo));
    if (!bo) {
        close(dmabuf_fd);
        return NULL;
    }
    bo->gbm = gbm;
    bo->width = width;
    bo->height = height;
    bo->stride = stride;
    bo->format = format;
    bo->modifier = 0; /* DRM_FORMAT_MOD_LINEAR */
    bo->dmabuf_fd = dmabuf_fd;
    return bo;
}

struct gbm_bo *gbm_bo_create_with_modifiers(struct gbm_device *gbm, uint32_t width, uint32_t height,
                                            uint32_t format, const uint64_t *modifiers,
                                            const unsigned int count) {
    (void)modifiers; (void)count;
    return gbm_bo_create(gbm, width, height, format, 0);
}

struct gbm_bo *gbm_bo_create_with_modifiers2(struct gbm_device *gbm, uint32_t width, uint32_t height,
                                             uint32_t format, const uint64_t *modifiers,
                                             const unsigned int count, uint32_t flags) {
    (void)modifiers; (void)count;
    return gbm_bo_create(gbm, width, height, format, flags);
}

#define GBM_BO_IMPORT_FD          0x5503
#define GBM_BO_IMPORT_FD_MODIFIER 0x5504

struct gbm_import_fd_data {
    int fd;
    uint32_t width;
    uint32_t height;
    uint32_t stride;
    uint32_t format;
};

struct gbm_import_fd_modifier_data {
    uint32_t width;
    uint32_t height;
    uint32_t format;
    uint32_t num_fds;
    int fds[4];
    int strides[4];
    int offsets[4];
    uint64_t modifier;
};

struct gbm_bo *gbm_bo_import(struct gbm_device *gbm, uint32_t type, void *buffer, uint32_t flags) {
    (void)flags;
    if (!gbm || !buffer) return NULL;
    if (type == GBM_BO_IMPORT_FD) {
        struct gbm_import_fd_data *d = (struct gbm_import_fd_data *)buffer;
        int dup_fd = fcntl(d->fd, F_DUPFD_CLOEXEC, 0);
        if (dup_fd < 0) return NULL;
        struct gbm_bo *bo = calloc(1, sizeof(*bo));
        if (!bo) { close(dup_fd); return NULL; }
        bo->gbm = gbm;
        bo->width = d->width;
        bo->height = d->height;
        bo->stride = d->stride;
        bo->format = d->format;
        bo->modifier = 0;
        bo->dmabuf_fd = dup_fd;
        return bo;
    }
    if (type == GBM_BO_IMPORT_FD_MODIFIER) {
        struct gbm_import_fd_modifier_data *d = (struct gbm_import_fd_modifier_data *)buffer;
        if (d->num_fds == 0 || d->fds[0] < 0) return NULL;
        int dup_fd = fcntl(d->fds[0], F_DUPFD_CLOEXEC, 0);
        if (dup_fd < 0) return NULL;
        struct gbm_bo *bo = calloc(1, sizeof(*bo));
        if (!bo) { close(dup_fd); return NULL; }
        bo->gbm = gbm;
        bo->width = d->width;
        bo->height = d->height;
        bo->stride = (uint32_t)d->strides[0];
        bo->format = d->format;
        bo->modifier = d->modifier;
        bo->dmabuf_fd = dup_fd;
        return bo;
    }
    return NULL;
}

void gbm_bo_destroy(struct gbm_bo *bo) {
    if (!bo) return;
    if (bo->destroy_user_data)
        bo->destroy_user_data(bo, bo->user_data);
    if (bo->dmabuf_fd >= 0)
        close(bo->dmabuf_fd);
    free(bo);
}

uint32_t gbm_bo_get_width(struct gbm_bo *bo) { return bo ? bo->width : 0; }
uint32_t gbm_bo_get_height(struct gbm_bo *bo) { return bo ? bo->height : 0; }
uint32_t gbm_bo_get_stride(struct gbm_bo *bo) { return bo ? bo->stride : 0; }
uint32_t gbm_bo_get_stride_for_plane(struct gbm_bo *bo, int plane) { (void)plane; return bo ? bo->stride : 0; }
uint32_t gbm_bo_get_format(struct gbm_bo *bo) { return bo ? bo->format : 0; }
uint32_t gbm_bo_get_bpp(struct gbm_bo *bo) { (void)bo; return 32; }
uint32_t gbm_bo_get_offset(struct gbm_bo *bo, int plane) { (void)bo; (void)plane; return 0; }
struct gbm_device *gbm_bo_get_device(struct gbm_bo *bo) { return bo ? bo->gbm : NULL; }
uint64_t gbm_bo_get_modifier(struct gbm_bo *bo) { return bo ? bo->modifier : 0; }
int gbm_bo_get_plane_count(struct gbm_bo *bo) { (void)bo; return 1; }

int gbm_bo_get_fd(struct gbm_bo *bo) {
    return (bo && bo->dmabuf_fd >= 0) ? fcntl(bo->dmabuf_fd, F_DUPFD_CLOEXEC, 0) : -1;
}

int gbm_bo_get_fd_for_plane(struct gbm_bo *bo, int plane) {
    (void)plane;
    return gbm_bo_get_fd(bo);
}

union gbm_bo_handle {
    void *ptr;
    int32_t s32;
    uint32_t u32;
    int64_t s64;
    uint64_t u64;
};

union gbm_bo_handle gbm_bo_get_handle(struct gbm_bo *bo) {
    union gbm_bo_handle h = { .u32 = bo ? 1 : 0 };
    return h;
}

union gbm_bo_handle gbm_bo_get_handle_for_plane(struct gbm_bo *bo, int plane) {
    (void)plane;
    return gbm_bo_get_handle(bo);
}

void *gbm_bo_map(struct gbm_bo *bo, uint32_t x, uint32_t y, uint32_t width, uint32_t height,
                 uint32_t flags, uint32_t *stride, void **map_data) {
    (void)x; (void)y; (void)width; (void)height; (void)flags;
    if (!bo || bo->dmabuf_fd < 0) return NULL;
    size_t len = (size_t)bo->stride * (size_t)bo->height;
    void *p = obtener_real_mmap()(NULL, len, PROT_READ | PROT_WRITE, MAP_SHARED, bo->dmabuf_fd, 0);
    if (p == MAP_FAILED) return NULL;
    if (stride) *stride = bo->stride;
    if (map_data) *map_data = p;
    return p;
}

void gbm_bo_unmap(struct gbm_bo *bo, void *map_data) {
    if (!bo || !map_data) return;
    munmap(map_data, (size_t)bo->stride * (size_t)bo->height);
}

void gbm_bo_set_user_data(struct gbm_bo *bo, void *data,
                          void (*destroy_user_data)(struct gbm_bo *, void *)) {
    if (!bo) return;
    bo->user_data = data;
    bo->destroy_user_data = destroy_user_data;
}

void *gbm_bo_get_user_data(struct gbm_bo *bo) {
    return bo ? bo->user_data : NULL;
}

/* Enlaza el EGLDevice software/Zink de Mesa con /dev/dri/renderD128 para CHyprOpenGLImpl
   y redirige EGL_PLATFORM_GBM_KHR (0x31D7) a EGL_PLATFORM_DEVICE_EXT (0x313F). */
static void *(*real_eglGetProcAddress_fn)(const char *);
static const char *(*real_eglQueryDeviceStringEXT)(void *, int);
static int (*real_eglQueryDevicesEXT)(int, void **, int *);
static void *(*real_eglGetPlatformDisplayEXT)(unsigned int, void *, const int *);
static void *(*real_eglGetPlatformDisplay)(unsigned int, void *, const intptr_t *);

static void inicializar_egl_ptrs(void) {
    if (!real_eglGetProcAddress_fn)
        real_eglGetProcAddress_fn = dlsym(RTLD_NEXT, "eglGetProcAddress");
    if (!real_eglGetPlatformDisplay)
        real_eglGetPlatformDisplay = dlsym(RTLD_NEXT, "eglGetPlatformDisplay");
    if (real_eglGetProcAddress_fn) {
        if (!real_eglQueryDevicesEXT)
            real_eglQueryDevicesEXT = real_eglGetProcAddress_fn("eglQueryDevicesEXT");
        if (!real_eglGetPlatformDisplayEXT)
            real_eglGetPlatformDisplayEXT = real_eglGetProcAddress_fn("eglGetPlatformDisplayEXT");
    }
}

static void *obtener_egl_device_sw(void) {
    inicializar_egl_ptrs();
    if (!real_eglQueryDevicesEXT) return NULL;
    void *devs[8] = {0};
    int n = 0;
    if (real_eglQueryDevicesEXT(8, devs, &n) && n > 0)
        return devs[0];
    return NULL;
}

static const char *shim_eglQueryDeviceStringEXT(void *device, int name) {
    if (name == 0x3233 /* EGL_DRM_DEVICE_FILE_EXT */ ||
        name == 0x3377 /* EGL_DRM_RENDER_NODE_FILE_EXT */) {
        return "/dev/dri/renderD128";
    }
    if (real_eglQueryDeviceStringEXT)
        return real_eglQueryDeviceStringEXT(device, name);
    return NULL;
}

static void *shim_eglGetPlatformDisplayEXT(unsigned int platform, void *native_display, const int *attrib_list) {
    inicializar_egl_ptrs();
    if (platform == 0x31D7 /* EGL_PLATFORM_GBM_KHR */) {
        void *sw_dev = obtener_egl_device_sw();
        if (sw_dev && real_eglGetPlatformDisplayEXT)
            return real_eglGetPlatformDisplayEXT(0x313F /* EGL_PLATFORM_DEVICE_EXT */, sw_dev, NULL);
    }
    if (real_eglGetPlatformDisplayEXT)
        return real_eglGetPlatformDisplayEXT(platform, native_display, attrib_list);
    return NULL;
}

void *eglGetPlatformDisplay(unsigned int platform, void *native_display, const intptr_t *attrib_list) {
    inicializar_egl_ptrs();
    if (platform == 0x31D7 /* EGL_PLATFORM_GBM_KHR */) {
        void *sw_dev = obtener_egl_device_sw();
        if (sw_dev && real_eglGetPlatformDisplayEXT)
            return real_eglGetPlatformDisplayEXT(0x313F /* EGL_PLATFORM_DEVICE_EXT */, sw_dev, NULL);
    }
    if (real_eglGetPlatformDisplay)
        return real_eglGetPlatformDisplay(platform, native_display, attrib_list);
    return NULL;
}

void *eglGetPlatformDisplayEXT(unsigned int platform, void *native_display, const int *attrib_list) {
    return shim_eglGetPlatformDisplayEXT(platform, native_display, attrib_list);
}

void *eglGetProcAddress(const char *procname) {
    inicializar_egl_ptrs();
    void *res = real_eglGetProcAddress_fn ? real_eglGetProcAddress_fn(procname) : NULL;
    if (!procname) return res;
    if (strcmp(procname, "eglQueryDeviceStringEXT") == 0) {
        real_eglQueryDeviceStringEXT = (const char *(*)(void *, int))res;
        return (void *)shim_eglQueryDeviceStringEXT;
    }
    if (strcmp(procname, "eglGetPlatformDisplayEXT") == 0) {
        if (res) real_eglGetPlatformDisplayEXT = (void *(*)(unsigned int, void *, const int *))res;
        return (void *)shim_eglGetPlatformDisplayEXT;
    }
    if (strcmp(procname, "eglGetPlatformDisplay") == 0) {
        if (res) real_eglGetPlatformDisplay = (void *(*)(unsigned int, void *, const intptr_t *))res;
        return (void *)eglGetPlatformDisplay;
    }
    return res;
}

/* Recorta versiones de wl_seat (v9->v7) y xdg_wm_base (v6->v5) si el cliente
   hace wl_registry_bind con una versión mayor a la publicada por el anfitrión. */
struct wl_interface_head {
    const char *name;
    int version;
};

void *wl_proxy_marshal_flags(void *proxy, uint32_t opcode,
                             const struct wl_interface_head *interface,
                             uint32_t version, uint32_t flags,
                             uintptr_t a0, uintptr_t a1, uintptr_t a2,
                             uintptr_t a3, uintptr_t a4, uintptr_t a5,
                             uintptr_t a6, uintptr_t a7) {
    static void *(*real_fn)(void *, uint32_t, const void *, uint32_t, uint32_t,
                            uintptr_t, uintptr_t, uintptr_t, uintptr_t,
                            uintptr_t, uintptr_t, uintptr_t, uintptr_t);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "wl_proxy_marshal_flags");
    if (opcode == 0 && interface && interface->name && a1 != 0 &&
        a2 == version && strcmp((const char *)a1, interface->name) == 0) {
        if (strcmp(interface->name, "wl_seat") == 0 && version > 7) {
            version = 7;
            a2 = 7;
        } else if (strcmp(interface->name, "xdg_wm_base") == 0 && version > 5) {
            version = 5;
            a2 = 5;
        }
    }
    return real_fn(proxy, opcode, interface, version, flags,
                   a0, a1, a2, a3, a4, a5, a6, a7);
}
