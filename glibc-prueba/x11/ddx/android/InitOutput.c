/*

Copyright 1993, 1998  The Open Group

Permission to use, copy, modify, distribute, and sell this software and its
documentation for any purpose is hereby granted without fee, provided that
the above copyright notice appear in all copies and that both that
copyright notice and this permission notice appear in supporting
documentation.

The above copyright notice and this permission notice shall be included
in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE OPEN GROUP BE LIABLE FOR ANY CLAIM, DAMAGES OR
OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.

Except as contained in this notice, the name of The Open Group shall
not be used in advertising or otherwise to promote the sale, use or
other dealings in this Software without prior written authorization
from The Open Group.

*/

#ifdef HAVE_DIX_CONFIG_H
#include <dix-config.h>
#endif

/* API 31 (ASurfaceTransaction_setPosition/setScale) como símbolos débiles, igual que anfitrion.c: en Android 11 no existen */
#define __ANDROID_UNAVAILABLE_SYMBOLS_ARE_WEAK__

#if defined(WIN32)
#include <X11/Xwinsock.h>
#endif
#include <stdio.h>
#include <X11/X.h>
#include <X11/Xproto.h>
#include <X11/Xos.h>
#include "scrnintstr.h"
#include "servermd.h"
#define PSZ 8
#include "fb.h"
#include "colormapst.h"
#include "gcstruct.h"
#include "input.h"
#include "mipointer.h"
#include "micmap.h"
#include <sys/types.h>
#ifdef HAVE_MMAP
#include <sys/mman.h>
#ifndef MAP_FILE
#define MAP_FILE 0
#endif
#endif                          /* HAVE_MMAP */
#include <sys/stat.h>
#include <errno.h>
#ifndef WIN32
#include <sys/param.h>
#endif
#include <X11/XWDFile.h>
#ifdef HAS_SHM
#include <sys/ipc.h>
#include <sys/shm.h>
#endif                          /* HAS_SHM */
#include "dix.h"
#include "miline.h"
#include "glx_extinit.h"
#include "randrstr.h"
#include "damage.h"
#include "windowstr.h"
#include <android/native_window.h>
#include <android/hardware_buffer.h>
#include <android/surface_control.h>
#include <pthread.h>
#include <time.h>
#include <sys/eventfd.h>
#include <android/log.h>
#include "android.h"
#include <signal.h>

#define VFB_DEFAULT_WIDTH      1280
#define VFB_DEFAULT_HEIGHT     1024
#define VFB_DEFAULT_DEPTH        24
#define VFB_DEFAULT_WHITEPIXEL    1
#define VFB_DEFAULT_BLACKPIXEL    0
#define VFB_DEFAULT_LINEBIAS      0
#define XWD_WINDOW_NAME_LEN      60
#define HAL_BGRA_8888 5

typedef struct {
    int width;
    int paddedBytesWidth;
    int paddedWidth;
    int height;
    int depth;
    int bitsPerPixel;
    int sizeInBytes;
    int ncolors;
    char *pfbMemory;
    XWDColor *pXWDCmap;
    XWDFileHeader *pXWDHeader;
    Pixel blackPixel;
    Pixel whitePixel;
    unsigned int lineBias;
    CloseScreenProcPtr closeScreen;

    /* B36: NORMAL_MEMORY_FB son tres AHardwareBuffer: uno bloqueado para dibujar (mapa[dibujo]), uno en pantalla y
     * uno libre o por liberar. debe[i] es lo que a ese buffer le falta respecto al que se dibuja. */
    AHardwareBuffer *ahb[3];
    void *mapa[3];
    RegionRec debe[3];
    int dibujo;
    int presente;               /* el último entregado a SurfaceFlinger; -1 si ninguno */

#ifdef HAVE_MMAP
    int mmap_fd;
    char mmap_file[MAXPATHLEN];
#endif

#ifdef HAS_SHM
    int shmid;
#endif
} vfbScreenInfo, *vfbScreenInfoPtr;

static int vfbNumScreens;
static vfbScreenInfo *vfbScreens;

static vfbScreenInfo defaultScreenInfo = {
    .width = VFB_DEFAULT_WIDTH,
    .height = VFB_DEFAULT_HEIGHT,
    .depth = VFB_DEFAULT_DEPTH,
    .blackPixel = VFB_DEFAULT_BLACKPIXEL,
    .whitePixel = VFB_DEFAULT_WHITEPIXEL,
    .lineBias = VFB_DEFAULT_LINEBIAS,
};

static Bool vfbPixmapDepths[33];

#ifdef HAVE_MMAP
static char *pfbdir = NULL;
#endif
typedef enum { NORMAL_MEMORY_FB, SHARED_MEMORY_FB, MMAPPED_FILE_FB } fbMemType;
static fbMemType fbmemtype = NORMAL_MEMORY_FB;
static char needswap = 0;
static Bool Render = TRUE;

#define swapcopy16(_dst, _src) \
    if (needswap) { CARD16 _s = _src; cpswaps(_s, _dst); } \
    else _dst = _src;

#define swapcopy32(_dst, _src) \
    if (needswap) { CARD32 _s = _src; cpswapl(_s, _dst); } \
    else _dst = _src;

static void
vfbInitializePixmapDepths(void)
{
    int i;

    vfbPixmapDepths[1] = TRUE;  /* always need bitmaps */
    for (i = 2; i <= 32; i++)
        vfbPixmapDepths[i] = FALSE;
}

static int
vfbBitsPerPixel(int depth)
{
    if (depth == 1)
        return 1;
    else if (depth <= 8)
        return 8;
    else if (depth <= 16)
        return 16;
    else
        return 32;
}

static void
freeScreenInfo(vfbScreenInfoPtr pvfb)
{
    int i;

    switch (fbmemtype) {
#ifdef HAVE_MMAP
    case MMAPPED_FILE_FB:
        if (-1 == unlink(pvfb->mmap_file)) {
            perror("unlink");
            ErrorF("unlink %s failed, %s",
                   pvfb->mmap_file, strerror(errno));
        }
        break;
#else                           /* HAVE_MMAP */
    case MMAPPED_FILE_FB:
        break;
#endif                          /* HAVE_MMAP */

#ifdef HAS_SHM
    case SHARED_MEMORY_FB:
        if (-1 == shmdt((char *) pvfb->pXWDHeader)) {
            perror("shmdt");
            ErrorF("shmdt failed, %s", strerror(errno));
        }
        break;
#else                           /* HAS_SHM */
    case SHARED_MEMORY_FB:
        break;
#endif                          /* HAS_SHM */

    case NORMAL_MEMORY_FB:
        free(pvfb->pXWDHeader);
        for (i = 0; i < 3; i++) {
            if (pvfb->mapa[i])
                AHardwareBuffer_unlock(pvfb->ahb[i], NULL);
            if (pvfb->ahb[i])
                AHardwareBuffer_release(pvfb->ahb[i]);
            pvfb->ahb[i] = NULL;
            pvfb->mapa[i] = NULL;
        }
        break;
    }
}

void
ddxGiveUp(enum ExitCode error)
{
    int i;

    /* clean up the framebuffers */
    for (i = 0; i < vfbNumScreens; i++) {
        freeScreenInfo(&vfbScreens[i]);
    }
}

#ifdef __APPLE__
void
DarwinHandleGUI(int argc, char *argv[])
{
}
#endif

void
OsVendorInit(void)
{
}

void
OsVendorFatalError(const char *f, va_list args)
{
}

#if defined(DDXBEFORERESET)
void
ddxBeforeReset(void)
{
    return;
}
#endif

#if INPUTTHREAD
/** This function is called in Xserver/os/inputthread.c when starting
    the input thread. */
void
ddxInputThreadInit(void)
{
}
#endif

void
ddxUseMsg(void)
{
    ErrorF("-screen scrn WxHxD     set screen's width, height, depth\n");
    ErrorF("-pixdepths list-of-int support given pixmap depths\n");
    ErrorF("+/-render		   turn on/off RENDER extension support"
           "(default on)\n");
    ErrorF("-linebias n            adjust thin line pixelization\n");
    ErrorF("-blackpixel n          pixel value for black\n");
    ErrorF("-whitepixel n          pixel value for white\n");

#ifdef HAVE_MMAP
    ErrorF
        ("-fbdir directory       put framebuffers in mmap'ed files in directory\n");
#endif

#ifdef HAS_SHM
    ErrorF("-shmem                 put framebuffers in shared memory\n");
#endif
}

int
ddxProcessArgument(int argc, char *argv[], int i)
{
    static Bool firstTime = TRUE;
    static int lastScreen = -1;
    vfbScreenInfo *currentScreen;

    if (firstTime) {
        vfbInitializePixmapDepths();
        firstTime = FALSE;
    }

    if (lastScreen == -1)
        currentScreen = &defaultScreenInfo;
    else
        currentScreen = &vfbScreens[lastScreen];

    if (strcmp(argv[i], "-screen") == 0) {      /* -screen n WxHxD */
        int screenNum;

        CHECK_FOR_REQUIRED_ARGUMENTS(2);
        screenNum = atoi(argv[i + 1]);
        /* The protocol only has a CARD8 for number of screens in the
           connection setup block, so don't allow more than that. */
        if ((screenNum < 0) || (screenNum >= 255)) {
            ErrorF("Invalid screen number %d\n", screenNum);
            UseMsg();
            FatalError("Invalid screen number %d passed to -screen\n",
                       screenNum);
        }

        if (vfbNumScreens <= screenNum) {
            vfbScreens =
                reallocarray(vfbScreens, screenNum + 1, sizeof(*vfbScreens));
            if (!vfbScreens)
                FatalError("Not enough memory for screen %d\n", screenNum);
            for (; vfbNumScreens <= screenNum; ++vfbNumScreens)
                vfbScreens[vfbNumScreens] = defaultScreenInfo;
        }

        if (3 != sscanf(argv[i + 2], "%dx%dx%d",
                        &vfbScreens[screenNum].width,
                        &vfbScreens[screenNum].height,
                        &vfbScreens[screenNum].depth)) {
            ErrorF("Invalid screen configuration %s\n", argv[i + 2]);
            UseMsg();
            FatalError("Invalid screen configuration %s for -screen %d\n",
                       argv[i + 2], screenNum);
        }

        lastScreen = screenNum;
        return 3;
    }

    if (strcmp(argv[i], "-pixdepths") == 0) {   /* -pixdepths list-of-depth */
        int depth, ret = 1;

        CHECK_FOR_REQUIRED_ARGUMENTS(1);
        while ((++i < argc) && (depth = atoi(argv[i])) != 0) {
            if (depth < 0 || depth > 32) {
                ErrorF("Invalid pixmap depth %d\n", depth);
                UseMsg();
                FatalError("Invalid pixmap depth %d passed to -pixdepths\n",
                           depth);
            }
            vfbPixmapDepths[depth] = TRUE;
            ret++;
        }
        return ret;
    }

    if (strcmp(argv[i], "+render") == 0) {      /* +render */
        Render = TRUE;
        return 1;
    }

    if (strcmp(argv[i], "-render") == 0) {      /* -render */
        Render = FALSE;
#ifdef COMPOSITE
        noCompositeExtension = TRUE;
#endif
        return 1;
    }

    if (strcmp(argv[i], "-blackpixel") == 0) {  /* -blackpixel n */
        CHECK_FOR_REQUIRED_ARGUMENTS(1);
        currentScreen->blackPixel = atoi(argv[++i]);
        return 2;
    }

    if (strcmp(argv[i], "-whitepixel") == 0) {  /* -whitepixel n */
        CHECK_FOR_REQUIRED_ARGUMENTS(1);
        currentScreen->whitePixel = atoi(argv[++i]);
        return 2;
    }

    if (strcmp(argv[i], "-linebias") == 0) {    /* -linebias n */
        CHECK_FOR_REQUIRED_ARGUMENTS(1);
        currentScreen->lineBias = atoi(argv[++i]);
        return 2;
    }

#ifdef HAVE_MMAP
    if (strcmp(argv[i], "-fbdir") == 0) {       /* -fbdir directory */
        CHECK_FOR_REQUIRED_ARGUMENTS(1);
        pfbdir = argv[++i];
        fbmemtype = MMAPPED_FILE_FB;
        return 2;
    }
#endif                          /* HAVE_MMAP */

#ifdef HAS_SHM
    if (strcmp(argv[i], "-shmem") == 0) {       /* -shmem */
        fbmemtype = SHARED_MEMORY_FB;
        return 1;
    }
#endif

    return 0;
}

static void
vfbInstallColormap(ColormapPtr pmap)
{
    ColormapPtr oldpmap = GetInstalledmiColormap(pmap->pScreen);

    if (pmap != oldpmap) {
        int entries;
        XWDFileHeader *pXWDHeader;
        VisualPtr pVisual;
        Pixel *ppix;
        xrgb *prgb;
        xColorItem *defs;
        int i;

        miInstallColormap(pmap);

        entries = pmap->pVisual->ColormapEntries;
        pXWDHeader = vfbScreens[pmap->pScreen->myNum].pXWDHeader;
        pVisual = pmap->pVisual;

        swapcopy32(pXWDHeader->visual_class, pVisual->class);
        swapcopy32(pXWDHeader->red_mask, pVisual->redMask);
        swapcopy32(pXWDHeader->green_mask, pVisual->greenMask);
        swapcopy32(pXWDHeader->blue_mask, pVisual->blueMask);
        swapcopy32(pXWDHeader->bits_per_rgb, pVisual->bitsPerRGBValue);
        swapcopy32(pXWDHeader->colormap_entries, pVisual->ColormapEntries);

        ppix = xallocarray(entries, sizeof(Pixel));
        prgb = xallocarray(entries, sizeof(xrgb));
        defs = xallocarray(entries, sizeof(xColorItem));

        for (i = 0; i < entries; i++)
            ppix[i] = i;
        /* XXX truecolor */
        QueryColors(pmap, entries, ppix, prgb, serverClient);

        for (i = 0; i < entries; i++) { /* convert xrgbs to xColorItems */
            defs[i].pixel = ppix[i] & 0xff;     /* change pixel to index */
            defs[i].red = prgb[i].red;
            defs[i].green = prgb[i].green;
            defs[i].blue = prgb[i].blue;
            defs[i].flags = DoRed | DoGreen | DoBlue;
        }
        (*pmap->pScreen->StoreColors) (pmap, entries, defs);

        free(ppix);
        free(prgb);
        free(defs);
    }
}

static void
vfbStoreColors(ColormapPtr pmap, int ndef, xColorItem * pdefs)
{
    XWDColor *pXWDCmap;
    int i;

    if (pmap != GetInstalledmiColormap(pmap->pScreen)) {
        return;
    }

    pXWDCmap = vfbScreens[pmap->pScreen->myNum].pXWDCmap;

    if ((pmap->pVisual->class | DynamicClass) == DirectColor) {
        return;
    }

    for (i = 0; i < ndef; i++) {
        if (pdefs[i].flags & DoRed) {
            swapcopy16(pXWDCmap[pdefs[i].pixel].red, pdefs[i].red);
        }
        if (pdefs[i].flags & DoGreen) {
            swapcopy16(pXWDCmap[pdefs[i].pixel].green, pdefs[i].green);
        }
        if (pdefs[i].flags & DoBlue) {
            swapcopy16(pXWDCmap[pdefs[i].pixel].blue, pdefs[i].blue);
        }
    }
}

#ifdef HAVE_MMAP

/* this flushes any changes to the screens out to the mmapped file */
static void
vfbBlockHandler(void *blockData, void *timeout)
{
    int i;

    for (i = 0; i < vfbNumScreens; i++) {
#ifdef MS_ASYNC
        if (-1 == msync((caddr_t) vfbScreens[i].pXWDHeader,
                        (size_t) vfbScreens[i].sizeInBytes, MS_ASYNC))
#else
        /* silly NetBSD and who else? */
        if (-1 == msync((caddr_t) vfbScreens[i].pXWDHeader,
                        (size_t) vfbScreens[i].sizeInBytes))
#endif
        {
            perror("msync");
            ErrorF("msync failed, %s", strerror(errno));
        }
    }
}

static void
vfbWakeupHandler(void *blockData, int result)
{
}

static void
vfbAllocateMmappedFramebuffer(vfbScreenInfoPtr pvfb)
{
#define DUMMY_BUFFER_SIZE 65536
    char dummyBuffer[DUMMY_BUFFER_SIZE];
    int currentFileSize, writeThisTime;

    snprintf(pvfb->mmap_file, sizeof(pvfb->mmap_file), "%s/Xvfb_screen%d",
             pfbdir, (int) (pvfb - vfbScreens));
    if (-1 == (pvfb->mmap_fd = open(pvfb->mmap_file, O_CREAT | O_RDWR, 0666))) {
        perror("open");
        ErrorF("open %s failed, %s", pvfb->mmap_file, strerror(errno));
        return;
    }

    /* Extend the file to be the proper size */

    memset(dummyBuffer, 0, DUMMY_BUFFER_SIZE);
    for (currentFileSize = 0;
         currentFileSize < pvfb->sizeInBytes;
         currentFileSize += writeThisTime) {
        writeThisTime = min(DUMMY_BUFFER_SIZE,
                            pvfb->sizeInBytes - currentFileSize);
        if (-1 == write(pvfb->mmap_fd, dummyBuffer, writeThisTime)) {
            perror("write");
            ErrorF("write %s failed, %s", pvfb->mmap_file, strerror(errno));
            return;
        }
    }

    /* try to mmap the file */

    pvfb->pXWDHeader = (XWDFileHeader *) mmap((caddr_t) NULL, pvfb->sizeInBytes,
                                              PROT_READ | PROT_WRITE,
                                              MAP_FILE | MAP_SHARED,
                                              pvfb->mmap_fd, 0);
    if (-1 == (long) pvfb->pXWDHeader) {
        perror("mmap");
        ErrorF("mmap %s failed, %s", pvfb->mmap_file, strerror(errno));
        pvfb->pXWDHeader = NULL;
        return;
    }

    if (!RegisterBlockAndWakeupHandlers(vfbBlockHandler, vfbWakeupHandler,
                                        NULL)) {
        pvfb->pXWDHeader = NULL;
    }
}
#endif                          /* HAVE_MMAP */

#ifdef HAS_SHM
static void
vfbAllocateSharedMemoryFramebuffer(vfbScreenInfoPtr pvfb)
{
    /* create the shared memory segment */

    pvfb->shmid = shmget(IPC_PRIVATE, pvfb->sizeInBytes, IPC_CREAT | 0777);
    if (pvfb->shmid < 0) {
        perror("shmget");
        ErrorF("shmget %d bytes failed, %s", pvfb->sizeInBytes,
               strerror(errno));
        return;
    }

    /* try to attach it */

    pvfb->pXWDHeader = (XWDFileHeader *) shmat(pvfb->shmid, 0, 0);
    if (-1 == (long) pvfb->pXWDHeader) {
        perror("shmat");
        ErrorF("shmat failed, %s", strerror(errno));
        pvfb->pXWDHeader = NULL;
        return;
    }

    ErrorF("screen %d shmid %d\n", (int) (pvfb - vfbScreens), pvfb->shmid);
}
#endif                          /* HAS_SHM */

/* B36: los tres AHardwareBuffer de la pantalla, del tamaño del servidor. El stride que dice gralloc manda: de él
 * salen paddedBytesWidth y paddedWidth. El primero queda bloqueado para que fb dibuje en él. */
static Bool
androidReservarPantalla(vfbScreenInfoPtr pvfb)
{
    AHardwareBuffer_Desc desc = {
        .width = pvfb->width,
        .height = pvfb->height,
        .layers = 1,
        .format = HAL_BGRA_8888,
        .usage = AHARDWAREBUFFER_USAGE_CPU_READ_OFTEN | AHARDWAREBUFFER_USAGE_CPU_WRITE_OFTEN |
                 AHARDWAREBUFFER_USAGE_GPU_SAMPLED_IMAGE | AHARDWAREBUFFER_USAGE_COMPOSER_OVERLAY,
    };
    BoxRec todaLaPantalla = { 0, 0, pvfb->width, pvfb->height };
    int i;

    for (i = 0; i < 3; i++) {
        if (AHardwareBuffer_allocate(&desc, &pvfb->ahb[i]) != 0) {
            ErrorF("AHardwareBuffer_allocate %dx%d falló\n", pvfb->width, pvfb->height);
            return FALSE;
        }
    }
    AHardwareBuffer_describe(pvfb->ahb[0], &desc);
    pvfb->paddedWidth = desc.stride;
    pvfb->paddedBytesWidth = desc.stride * 4;
    if (AHardwareBuffer_lock(pvfb->ahb[0], AHARDWAREBUFFER_USAGE_CPU_READ_OFTEN |
                             AHARDWAREBUFFER_USAGE_CPU_WRITE_OFTEN, -1, NULL, &pvfb->mapa[0]) != 0) {
        ErrorF("AHardwareBuffer_lock falló\n");
        return FALSE;
    }
    pvfb->dibujo = 0;
    pvfb->presente = -1;
    /* los otros dos nacen sin contenido: les falta la pantalla entera */
    RegionInit(&pvfb->debe[0], NULL, 0);
    RegionInit(&pvfb->debe[1], &todaLaPantalla, 1);
    RegionInit(&pvfb->debe[2], &todaLaPantalla, 1);
    return TRUE;
}

static char *
vfbAllocateFramebufferMemory(vfbScreenInfoPtr pvfb)
{
    if (pvfb->pfbMemory)
        return pvfb->pfbMemory; /* already done */

    if (fbmemtype == NORMAL_MEMORY_FB && !androidReservarPantalla(pvfb))
        return NULL;
    pvfb->sizeInBytes = pvfb->paddedBytesWidth * pvfb->height;

    /* Calculate how many entries in colormap.  This is rather bogus, because
     * the visuals haven't even been set up yet, but we need to know because we
     * have to allocate space in the file for the colormap.  The number 10
     * below comes from the MAX_PSEUDO_DEPTH define in cfbcmap.c.
     */

    if (pvfb->depth <= 10) {    /* single index colormaps */
        pvfb->ncolors = 1 << pvfb->depth;
    }
    else {                      /* decomposed colormaps */
        int nplanes_per_color_component = pvfb->depth / 3;

        if (pvfb->depth % 3)
            nplanes_per_color_component++;
        pvfb->ncolors = 1 << nplanes_per_color_component;
    }

    /* add extra bytes for XWDFileHeader, window name, and colormap */

    pvfb->sizeInBytes += SIZEOF(XWDheader) + XWD_WINDOW_NAME_LEN +
        pvfb->ncolors * SIZEOF(XWDColor);

    pvfb->pXWDHeader = NULL;
    switch (fbmemtype) {
#ifdef HAVE_MMAP
    case MMAPPED_FILE_FB:
        vfbAllocateMmappedFramebuffer(pvfb);
        break;
#else
    case MMAPPED_FILE_FB:
        break;
#endif

#ifdef HAS_SHM
    case SHARED_MEMORY_FB:
        vfbAllocateSharedMemoryFramebuffer(pvfb);
        break;
#else
    case SHARED_MEMORY_FB:
        break;
#endif

    case NORMAL_MEMORY_FB:
        /* solo la cabecera XWD y el mapa de colores; los píxeles están en los AHardwareBuffer */
        pvfb->pXWDHeader = (XWDFileHeader *)
            malloc(pvfb->sizeInBytes - (size_t) pvfb->paddedBytesWidth * pvfb->height);
        break;
    }

    if (pvfb->pXWDHeader) {
        pvfb->pXWDCmap = (XWDColor *) ((char *) pvfb->pXWDHeader
                                       + SIZEOF(XWDheader) +
                                       XWD_WINDOW_NAME_LEN);
        pvfb->pfbMemory = fbmemtype == NORMAL_MEMORY_FB ? pvfb->mapa[0] :
            (char *) (pvfb->pXWDCmap + pvfb->ncolors);

        return pvfb->pfbMemory;
    }

    return NULL;
}

static void
vfbWriteXWDFileHeader(ScreenPtr pScreen)
{
    vfbScreenInfoPtr pvfb = &vfbScreens[pScreen->myNum];
    XWDFileHeader *pXWDHeader = pvfb->pXWDHeader;
    char hostname[XWD_WINDOW_NAME_LEN];
    unsigned long swaptest = 1;
    int i;

    needswap = *(char *) &swaptest;

    pXWDHeader->header_size =
        (char *) pvfb->pXWDCmap - (char *) pvfb->pXWDHeader;
    pXWDHeader->file_version = XWD_FILE_VERSION;

    pXWDHeader->pixmap_format = ZPixmap;
    pXWDHeader->pixmap_depth = pvfb->depth;
    pXWDHeader->pixmap_height = pXWDHeader->window_height = pvfb->height;
    pXWDHeader->xoffset = 0;
    pXWDHeader->byte_order = IMAGE_BYTE_ORDER;
    pXWDHeader->bitmap_bit_order = BITMAP_BIT_ORDER;
#ifndef INTERNAL_VS_EXTERNAL_PADDING
    pXWDHeader->pixmap_width = pXWDHeader->window_width = pvfb->width;
    pXWDHeader->bitmap_unit = BITMAP_SCANLINE_UNIT;
    pXWDHeader->bitmap_pad = BITMAP_SCANLINE_PAD;
#else
    pXWDHeader->pixmap_width = pXWDHeader->window_width = pvfb->paddedWidth;
    pXWDHeader->bitmap_unit = BITMAP_SCANLINE_UNIT_PROTO;
    pXWDHeader->bitmap_pad = BITMAP_SCANLINE_PAD_PROTO;
#endif
    pXWDHeader->bits_per_pixel = pvfb->bitsPerPixel;
    pXWDHeader->bytes_per_line = pvfb->paddedBytesWidth;
    pXWDHeader->ncolors = pvfb->ncolors;

    /* visual related fields are written when colormap is installed */

    pXWDHeader->window_x = pXWDHeader->window_y = 0;
    pXWDHeader->window_bdrwidth = 0;

    /* write xwd "window" name: Xvfb hostname:server.screen */

    if (-1 == gethostname(hostname, sizeof(hostname)))
        hostname[0] = 0;
    else
        hostname[XWD_WINDOW_NAME_LEN - 1] = 0;
    sprintf((char *) (pXWDHeader + 1), "Xvfb %s:%s.%d", hostname, display,
            pScreen->myNum);

    /* write colormap pixel slot values */

    for (i = 0; i < pvfb->ncolors; i++) {
        pvfb->pXWDCmap[i].pixel = i;
    }

    /* byte swap to most significant byte first */

    if (needswap) {
        SwapLongs((CARD32 *) pXWDHeader, SIZEOF(XWDheader) / 4);
        for (i = 0; i < pvfb->ncolors; i++) {
            swapl(&pvfb->pXWDCmap[i].pixel);
        }
    }
}

static Bool
vfbCursorOffScreen(ScreenPtr *ppScreen, int *x, int *y)
{
    return FALSE;
}

static void
vfbCrossScreen(ScreenPtr pScreen, Bool entering)
{
}

static miPointerScreenFuncRec vfbPointerCursorFuncs = {
    vfbCursorOffScreen,
    vfbCrossScreen,
    miPointerWarpCursor
};


/* B11: la entrega a la surface. Damage anota lo que dibujan los clientes y el block handler
 * (lo que corre antes de que el servidor duerma) entrega el AHardwareBuffer a SurfaceFlinger y pasa a dibujar en el
 * otro, al que copia lo dibujado. */
static ANativeWindow *ventana;
static ASurfaceControl *capa;
static DamagePtr danio;
static Bool ventana_nueva;
static WindowPtr tapa;

/* present/present_fake.c (parche): retiene los avisos de vblank mientras no hay ventana */
void present_fake_pausar(Bool pausar);

/* Sin ventana, una ventana del servidor encima de todo: las demás quedan tapadas, su dibujo se recorta a nada y
 * reciben VisibilityNotify (para lo que no espera a Present, como Openbox sin compositor). Fondo None: no pinta nada
 * al mapearse. Al quitarla cada una recibe Expose y se redibuja. */
static void
androidTapar(Bool tapar)
{
    ScreenPtr pScreen = screenInfo.screens[0];
    XID si = xTrue, arriba = Above;
    int error;

    if (!pScreen || !pScreen->root)
        return;
    if (!tapar) {
        if (tapa && tapa->mapped)
            UnmapWindow(tapa, FALSE);
        return;
    }
    if (!tapa) {
        XID id = FakeClientID(0);

        tapa = CreateWindow(id, pScreen->root, 0, 0, pScreen->width, pScreen->height, 0, InputOutput,
                            CWOverrideRedirect, &si, pScreen->rootDepth, serverClient,
                            wVisual(pScreen->root), &error);
        if (!tapa || !AddResource(id, RT_WINDOW, tapa)) {
            tapa = NULL;
            return;
        }
    }
    ConfigureWindow(tapa, CWStackMode, &arriba, serverClient);
    if (!tapa->mapped)
        MapWindow(tapa, serverClient);
}

static pthread_mutex_t liberacion_mtx = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t liberacion_cond = PTHREAD_COND_INITIALIZER;
/* por buffer: SurfaceFlinger ya lo soltó (liberado) y con qué fence (-1: ya está libre) */
static Bool liberado[3] = { TRUE, TRUE, TRUE };
static int liberacion_fence[3] = { -1, -1, -1 };
/* A lo más una transacción en vuelo: hasta su OnComplete el daño se acumula y no se entrega. Así el buffer libre
 * siempre llegó ya y no se espera su fence. El OnComplete despierta al servidor por el eventfd `despertar`. */
static Bool en_vuelo;
static CARD32 en_vuelo_desde;
static int despertar = -1;

void
androidVentana(ANativeWindow *nueva)
{
    present_fake_pausar(nueva == NULL);
    androidTapar(nueva == NULL);
    if (capa) {
        ASurfaceTransaction *tr = ASurfaceTransaction_create();

        ASurfaceTransaction_reparent(tr, capa, NULL);
        ASurfaceTransaction_apply(tr);
        ASurfaceTransaction_delete(tr);
        ASurfaceControl_release(capa);
        capa = NULL;
        pthread_mutex_lock(&liberacion_mtx);
        en_vuelo = FALSE;
        pthread_mutex_unlock(&liberacion_mtx);
    }
    if (ventana)
        ANativeWindow_release(ventana);
    ventana = nueva;
    ventana_nueva = TRUE;
    if (ventana)
        capa = ASurfaceControl_createFromWindow(ventana, "x11");
}

/* OnComplete corre en un hilo de binder: deja la release fence del buffer que esta transacción reemplazó
 * (`anterior`) para que el block handler la recoja cuando vuelva a necesitarlo. */
typedef struct {
    ASurfaceControl *capa;
    int anterior;
} androidTransaccion;


static void
androidTransaccionCompleta(void *ctx, ASurfaceTransactionStats *stats)
{
    androidTransaccion *t = ctx;
    int fence = ASurfaceTransactionStats_getPreviousReleaseFenceFd(stats, t->capa);

    ASurfaceControl_release(t->capa);
    pthread_mutex_lock(&liberacion_mtx);
    if (t->anterior >= 0) {
        if (liberacion_fence[t->anterior] >= 0)
            close(liberacion_fence[t->anterior]);
        liberacion_fence[t->anterior] = fence;
        liberado[t->anterior] = TRUE;
        pthread_cond_broadcast(&liberacion_cond);
    }
    else if (fence >= 0)
        close(fence);
    en_vuelo = FALSE;
    pthread_mutex_unlock(&liberacion_mtx);
    free(t);
    if (despertar >= 0) {
        uint64_t uno = 1;

        (void) write(despertar, &uno, sizeof(uno));
    }
}

/* Solo vacía el eventfd: despertar basta para que el block handler vuelva a correr y entregue lo pendiente. */
static void
androidDespertado(int fd, int ready, void *data)
{
    uint64_t n;

    (void) read(fd, &n, sizeof(n));
}

/* La fence con la que SurfaceFlinger soltó el buffer i; -1 si ya está libre o no contestó a tiempo. Con tres buffers
 * el aviso ya llegó en la transacción anterior y no se espera. */
static int
androidEsperarLiberacion(int i)
{
    struct timespec limite;
    int fence;

    clock_gettime(CLOCK_REALTIME, &limite);
    limite.tv_nsec += 100 * 1000 * 1000;
    if (limite.tv_nsec >= 1000000000) {
        limite.tv_sec++;
        limite.tv_nsec -= 1000000000;
    }
    pthread_mutex_lock(&liberacion_mtx);
    if (!liberado[i]) {
        CARD32 desde = GetTimeInMillis();

        while (!liberado[i] && pthread_cond_timedwait(&liberacion_cond, &liberacion_mtx, &limite) == 0)
            ;
        /* con una sola transacción en vuelo no debería pasar: lo cuenta pruebas/x11/arrastre.sh */
        __android_log_print(ANDROID_LOG_WARN, "x11", "esperó %u ms la liberación del buffer %d",
                            (unsigned) (GetTimeInMillis() - desde), i);
    }
    fence = liberado[i] ? liberacion_fence[i] : -1;
    liberacion_fence[i] = -1;
    pthread_mutex_unlock(&liberacion_mtx);
    return fence;
}

/* Copia las cajas de region del AHardwareBuffer `de` al `a` (ya bloqueado para escribir). */
static void
androidCopiarDanio(vfbScreenInfoPtr pvfb, int de, int a, RegionPtr region)
{
    BoxPtr cajas = RegionRects(region);
    int i, n = RegionNumRects(region), y;
    void *origen;

    if (AHardwareBuffer_lock(pvfb->ahb[de], AHARDWAREBUFFER_USAGE_CPU_READ_OFTEN, -1, NULL, &origen) != 0) {
        ErrorF("AHardwareBuffer_lock (lectura) falló\n");
        return;
    }
    for (i = 0; i < n; i++)
        for (y = cajas[i].y1; y < cajas[i].y2; y++) {
            size_t desde = (size_t) y * pvfb->paddedBytesWidth + (size_t) cajas[i].x1 * 4;

            memcpy((char *) pvfb->mapa[a] + desde, (char *) origen + desde, (size_t) (cajas[i].x2 - cajas[i].x1) * 4);
        }
    AHardwareBuffer_unlock(pvfb->ahb[de], NULL);
}

/* Entrega el buffer en que se dibujó a SurfaceFlinger (estirado al tamaño de la ventana) y pasa a dibujar en el
 * libre: el que no es el entregado ni el que esta transacción reemplaza. Ese ya llegó en el OnComplete anterior; solo
 * se espera si no. Se le copia lo que le falta (debe[]). FALSE: no hay capa, no se tocó nada. */
static Bool
androidPresentar(vfbScreenInfoPtr pvfb, RegionPtr region)
{
    ScreenPtr pScreen = screenInfo.screens[0];
    int actual = pvfb->dibujo, anterior = pvfb->presente, libre = -1, i, w, h, fence;
    ASurfaceTransaction *tr;
    androidTransaccion *t;

    if (!capa || !ventana)
        return FALSE;
    w = ANativeWindow_getWidth(ventana);
    h = ANativeWindow_getHeight(ventana);
    AHardwareBuffer_unlock(pvfb->ahb[actual], NULL);
    pvfb->mapa[actual] = NULL;
    for (i = 0; i < 3; i++)
        if (i != actual)
            RegionUnion(&pvfb->debe[i], &pvfb->debe[i], region);

    t = malloc(sizeof(*t));
    ASurfaceControl_acquire(capa);
    t->capa = capa;
    t->anterior = anterior;
    pthread_mutex_lock(&liberacion_mtx);
    liberado[actual] = FALSE;
    en_vuelo = TRUE;
    en_vuelo_desde = GetTimeInMillis();
    pthread_mutex_unlock(&liberacion_mtx);
    tr = ASurfaceTransaction_create();
    ASurfaceTransaction_setBuffer(tr, capa, pvfb->ahb[actual], -1);
    ASurfaceTransaction_setCrop(tr, capa, &(ARect) { 0, 0, pvfb->width, pvfb->height });
    if (ASurfaceTransaction_setScale) {
        ASurfaceTransaction_setPosition(tr, capa, 0, 0);
        ASurfaceTransaction_setScale(tr, capa, (float) w / pvfb->width, (float) h / pvfb->height);
    }
    ASurfaceTransaction_setBufferTransparency(tr, capa, ASURFACE_TRANSACTION_TRANSPARENCY_OPAQUE);
    ASurfaceTransaction_setVisibility(tr, capa, ASURFACE_TRANSACTION_VISIBILITY_SHOW);
    ASurfaceTransaction_setOnComplete(tr, t, androidTransaccionCompleta);
    ASurfaceTransaction_apply(tr);
    ASurfaceTransaction_delete(tr);
    pvfb->presente = actual;

    for (i = 0; i < 3; i++)
        if (i != actual && i != anterior && libre < 0)
            libre = i;
    fence = androidEsperarLiberacion(libre);
    if (AHardwareBuffer_lock(pvfb->ahb[libre], AHARDWAREBUFFER_USAGE_CPU_READ_OFTEN |
                             AHARDWAREBUFFER_USAGE_CPU_WRITE_OFTEN, fence, NULL, &pvfb->mapa[libre]) != 0)
        FatalError("AHardwareBuffer_lock del buffer de dibujo falló\n");
    androidCopiarDanio(pvfb, actual, libre, &pvfb->debe[libre]);
    RegionEmpty(&pvfb->debe[libre]);
    pvfb->dibujo = libre;
    pvfb->pfbMemory = pvfb->mapa[libre];
    pScreen->ModifyPixmapHeader(pScreen->GetScreenPixmap(pScreen), pvfb->width, pvfb->height, pvfb->depth,
                                pvfb->bitsPerPixel, pvfb->paddedBytesWidth, pvfb->mapa[libre]);
    return TRUE;
}

/* Damage destruye lo que cuelga de un pixmap cuando este se libera (p. ej. RandR cambia la pantalla): el
 * puntero ya no vale, se registra otro y se copia todo, porque lo anotado en el viejo se perdió. */
static void
androidDanioDestruido(DamagePtr d, void *closure)
{
    if (d == danio)
        danio = NULL;
    ventana_nueva = TRUE;
}

/* pScreen->BlockHandler que envuelve androidBlockHandler */
static ScreenBlockHandlerProcPtr bloqueo_envuelto;

/* Envuelve pScreen->BlockHandler y no es un block handler registrado: esos corren antes, y el cursor por software
 * (misprite, que se engancha encima cuando lo necesita) se repinta aquí; entregando antes el cuadro salía sin cursor. */
static void
androidBlockHandler(ScreenPtr pScreen, void *timeout)
{
    vfbScreenInfoPtr pvfb = &vfbScreens[0];
    RegionRec todo;
    Bool ocupado;

    pScreen->BlockHandler = bloqueo_envuelto;
    (*pScreen->BlockHandler) (pScreen, timeout);
    bloqueo_envuelto = pScreen->BlockHandler;
    pScreen->BlockHandler = androidBlockHandler;

    if (!danio) {
        if (!DamageSetup(pScreen))
            return;
        danio = DamageCreate(NULL, androidDanioDestruido, DamageReportNone, TRUE, pScreen, NULL);
        if (!danio)
            return;
        DamageRegister(&pScreen->GetScreenPixmap(pScreen)->drawable, danio);
    }
    if (!ventana || !capa)
        return;
    /* con una transacción en vuelo el daño sigue acumulándose; si su OnComplete no llega en 100 ms se da por perdida */
    pthread_mutex_lock(&liberacion_mtx);
    ocupado = en_vuelo && (CARD32) (GetTimeInMillis() - en_vuelo_desde) < 100;
    pthread_mutex_unlock(&liberacion_mtx);
    if (ocupado)
        return;
    if (ventana_nueva) {
        BoxRec todaLaPantalla = { 0, 0, pvfb->width, pvfb->height };

        RegionInit(&todo, &todaLaPantalla, 1);
    }
    else if (RegionNotEmpty(DamageRegion(danio))) {
        RegionInit(&todo, NULL, 0);
        RegionCopy(&todo, DamageRegion(danio));
    }
    else
        return;
    DamageEmpty(danio);
    /* sin capa nada salió: el cuadro completo queda pendiente */
    if (androidPresentar(pvfb, &todo))
        ventana_nueva = FALSE;
    else
        ventana_nueva = TRUE;
    RegionUninit(&todo);
}

static Bool
vfbCloseScreen(ScreenPtr pScreen)
{
    vfbScreenInfoPtr pvfb = &vfbScreens[pScreen->myNum];

    pScreen->CloseScreen = pvfb->closeScreen;
    /* el reinicio del servidor (se fue el último cliente) ya liberó la tapa con los demás recursos */
    tapa = NULL;

    /*
     * fb overwrites miCloseScreen, so do this here
     */
    if (pScreen->devPrivate)
        (*pScreen->DestroyPixmap) (pScreen->devPrivate);
    pScreen->devPrivate = NULL;

    return pScreen->CloseScreen(pScreen);
}

static Bool
vfbRROutputValidateMode(ScreenPtr           pScreen,
                        RROutputPtr         output,
                        RRModePtr           mode)
{
    rrScrPriv(pScreen);

    if (pScrPriv->minWidth <= mode->mode.width &&
        pScrPriv->maxWidth >= mode->mode.width &&
        pScrPriv->minHeight <= mode->mode.height &&
        pScrPriv->maxHeight >= mode->mode.height)
        return TRUE;
    else
        return FALSE;
}

static Bool
vfbRRScreenSetSize(ScreenPtr  pScreen,
                   CARD16     width,
                   CARD16     height,
                   CARD32     mmWidth,
                   CARD32     mmHeight)
{
    // Prevent screen updates while we change things around
    SetRootClip(pScreen, ROOT_CLIP_NONE);

    pScreen->width = width;
    pScreen->height = height;
    pScreen->mmWidth = mmWidth;
    pScreen->mmHeight = mmHeight;

    // Restore the ability to update screen, now with new dimensions
    SetRootClip(pScreen, ROOT_CLIP_FULL);

    RRScreenSizeNotify (pScreen);
    RRTellChanged(pScreen);

    return TRUE;
}

static Bool
vfbRRCrtcSet(ScreenPtr pScreen,
             RRCrtcPtr crtc,
             RRModePtr mode,
             int       x,
             int       y,
             Rotation  rotation,
             int       numOutput,
             RROutputPtr *outputs)
{
  return RRCrtcNotify(crtc, mode, x, y, rotation, NULL, numOutput, outputs);
}

static Bool
vfbRRGetInfo(ScreenPtr pScreen, Rotation *rotations)
{
    /* Don't support rotations */
    *rotations = RR_Rotate_0;

    return TRUE;
}

static Bool
vfbRandRInit(ScreenPtr pScreen)
{
    rrScrPrivPtr pScrPriv;
#if RANDR_12_INTERFACE
    RRModePtr  mode;
    RRCrtcPtr  crtc;
    RROutputPtr        output;
    xRRModeInfo modeInfo;
    char       name[64];
#endif

    if (!RRScreenInit (pScreen))
       return FALSE;
    pScrPriv = rrGetScrPriv(pScreen);
    pScrPriv->rrGetInfo = vfbRRGetInfo;
#if RANDR_12_INTERFACE
    pScrPriv->rrCrtcSet = vfbRRCrtcSet;
    pScrPriv->rrScreenSetSize = vfbRRScreenSetSize;
    pScrPriv->rrOutputSetProperty = NULL;
#if RANDR_13_INTERFACE
    pScrPriv->rrOutputGetProperty = NULL;
#endif
    pScrPriv->rrOutputValidateMode = vfbRROutputValidateMode;
    pScrPriv->rrModeDestroy = NULL;

    RRScreenSetSizeRange (pScreen,
                         1, 1,
                         pScreen->width, pScreen->height);

    sprintf (name, "%dx%d", pScreen->width, pScreen->height);
    memset (&modeInfo, '\0', sizeof (modeInfo));
    modeInfo.width = pScreen->width;
    modeInfo.height = pScreen->height;
    modeInfo.nameLength = strlen (name);

    mode = RRModeGet (&modeInfo, name);
    if (!mode)
       return FALSE;

    crtc = RRCrtcCreate (pScreen, NULL);
    if (!crtc)
       return FALSE;

    /* This is to avoid xrandr to complain about the gamma missing */
    RRCrtcGammaSetSize (crtc, 256);

    output = RROutputCreate (pScreen, "screen", 6, NULL);
    if (!output)
       return FALSE;
    if (!RROutputSetClones (output, NULL, 0))
       return FALSE;
    if (!RROutputSetModes (output, &mode, 1, 0))
       return FALSE;
    if (!RROutputSetCrtcs (output, &crtc, 1))
       return FALSE;
    if (!RROutputSetConnection (output, RR_Connected))
       return FALSE;
    RRCrtcNotify (crtc, mode, 0, 0, RR_Rotate_0, NULL, 1, &output);
#endif
    return TRUE;
}

static Bool
vfbScreenInit(ScreenPtr pScreen, int argc, char **argv)
{
    vfbScreenInfoPtr pvfb = &vfbScreens[pScreen->myNum];
    int dpix = monitorResolution, dpiy = monitorResolution;
    int ret;
    char *pbits;

    if (dpix == 0)
        dpix = 100;

    if (dpiy == 0)
        dpiy = 100;

    pvfb->bitsPerPixel = vfbBitsPerPixel(pvfb->depth);
    /* tras un reinicio del servidor el framebuffer ya existe y su stride es el de gralloc: no se recalcula */
    if (!pvfb->pfbMemory) {
        pvfb->paddedBytesWidth = PixmapBytePad(pvfb->width, pvfb->depth);
        if (pvfb->bitsPerPixel >= 8)
            pvfb->paddedWidth = pvfb->paddedBytesWidth / (pvfb->bitsPerPixel / 8);
        else
            pvfb->paddedWidth = pvfb->paddedBytesWidth * 8;
    }
    pbits = vfbAllocateFramebufferMemory(pvfb);
    if (!pbits)
        return FALSE;

    switch (pvfb->depth) {
    case 8:
        miSetVisualTypesAndMasks(8,
                                 ((1 << StaticGray) |
                                  (1 << GrayScale) |
                                  (1 << StaticColor) |
                                  (1 << PseudoColor) |
                                  (1 << TrueColor) |
                                  (1 << DirectColor)), 8, PseudoColor, 0, 0, 0);
        break;
    case 15:
        miSetVisualTypesAndMasks(15,
                                 ((1 << TrueColor) |
                                  (1 << DirectColor)),
                                 8, TrueColor, 0x7c00, 0x03e0, 0x001f);
        break;
    case 16:
        miSetVisualTypesAndMasks(16,
                                 ((1 << TrueColor) |
                                  (1 << DirectColor)),
                                 8, TrueColor, 0xf800, 0x07e0, 0x001f);
        break;
    case 24:
        miSetVisualTypesAndMasks(24,
                                 ((1 << TrueColor) |
                                  (1 << DirectColor)),
                                 8, TrueColor, 0xff0000, 0x00ff00, 0x0000ff);
        break;
    case 30:
        miSetVisualTypesAndMasks(30,
                                 ((1 << TrueColor) |
                                  (1 << DirectColor)),
                                 10, TrueColor, 0x3ff00000, 0x000ffc00,
                                 0x000003ff);
        break;
    default:
        return FALSE;
    }

    miSetPixmapDepths();

    ret = fbScreenInit(pScreen, pbits, pvfb->width, pvfb->height,
                       dpix, dpiy, pvfb->paddedWidth, pvfb->bitsPerPixel);
    if (ret && Render)
        fbPictureInit(pScreen, 0, 0);

    if (!ret)
        return FALSE;

    if (!vfbRandRInit(pScreen))
       return FALSE;

    pScreen->InstallColormap = vfbInstallColormap;
    pScreen->StoreColors = vfbStoreColors;

    /* Damage envuelve CreateGC: solo ve lo que dibujan los GC creados después. El cursor por software
     * (miDCDeviceInitialize, al iniciar el puntero) crea los suyos antes del primer block handler: sin esto lo
     * que pinta y lo que restaura bajo el cursor no se copia a la surface y quedan punteros viejos. */
    if (!DamageSetup(pScreen))
        return FALSE;

    miDCInitialize(pScreen, &vfbPointerCursorFuncs);

    bloqueo_envuelto = pScreen->BlockHandler;
    pScreen->BlockHandler = androidBlockHandler;
    if (despertar < 0)
        despertar = eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK);
    if (despertar < 0 || !SetNotifyFd(despertar, androidDespertado, X_NOTIFY_READ, NULL))
        return FALSE;

    vfbWriteXWDFileHeader(pScreen);

    pScreen->blackPixel = pvfb->blackPixel;
    pScreen->whitePixel = pvfb->whitePixel;

    ret = fbCreateDefColormap(pScreen);

    miSetZeroLineBias(pScreen, pvfb->lineBias);

    pvfb->closeScreen = pScreen->CloseScreen;
    pScreen->CloseScreen = vfbCloseScreen;

    return ret;

}                               /* end vfbScreenInit */

/* Depuración: con X11_CRASH_PASSTHRU Xorg no se traga el segfault; se restaura la acción por defecto, la
 * instrucción que falló se repite y Android escribe el tombstone con la pila. */
static int
androidSignal(int signo)
{
    if (!getenv("X11_CRASH_PASSTHRU"))
        return 1;
    signal(signo, SIG_DFL);
    return 0;
}

void
InitOutput(ScreenInfo * screen_info, int argc, char **argv)
{
    OsRegisterSigWrapper(androidSignal);

    int i;
    int NumFormats = 0;

    /* initialize pixmap formats */

    /* must have a pixmap depth to match every screen depth */
    for (i = 0; i < vfbNumScreens; i++) {
        vfbPixmapDepths[vfbScreens[i].depth] = TRUE;
    }

    /* RENDER needs a good set of pixmaps. */
    if (Render) {
        vfbPixmapDepths[1] = TRUE;
        vfbPixmapDepths[4] = TRUE;
        vfbPixmapDepths[8] = TRUE;
#if 0
        vfbPixmapDepths[12] = TRUE;
#endif
/*	vfbPixmapDepths[15] = TRUE; */
        vfbPixmapDepths[16] = TRUE;
        vfbPixmapDepths[24] = TRUE;
#if 0
        vfbPixmapDepths[30] = TRUE;
#endif
        vfbPixmapDepths[32] = TRUE;
    }

    xorgGlxCreateVendor();

    for (i = 1; i <= 32; i++) {
        if (vfbPixmapDepths[i]) {
            if (NumFormats >= MAXFORMATS)
                FatalError("MAXFORMATS is too small for this server\n");
            screen_info->formats[NumFormats].depth = i;
            screen_info->formats[NumFormats].bitsPerPixel = vfbBitsPerPixel(i);
            screen_info->formats[NumFormats].scanlinePad = BITMAP_SCANLINE_PAD;
            NumFormats++;
        }
    }

    screen_info->imageByteOrder = IMAGE_BYTE_ORDER;
    screen_info->bitmapScanlineUnit = BITMAP_SCANLINE_UNIT;
    screen_info->bitmapScanlinePad = BITMAP_SCANLINE_PAD;
    screen_info->bitmapBitOrder = BITMAP_BIT_ORDER;
    screen_info->numPixmapFormats = NumFormats;

    /* initialize screens */

    if (vfbNumScreens < 1) {
        vfbScreens = &defaultScreenInfo;
        vfbNumScreens = 1;
    }
    for (i = 0; i < vfbNumScreens; i++) {
        if (-1 == AddScreen(vfbScreenInit, argc, argv)) {
            FatalError("Couldn't add screen %d", i);
        }
    }

}                               /* end InitOutput */

int
androidAncho(void)
{
    return vfbScreens[0].width;
}

int
androidAlto(void)
{
    return vfbScreens[0].height;
}
