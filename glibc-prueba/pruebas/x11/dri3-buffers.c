/* B36: un cliente DRI3 recibe el dmabuf del AHardwareBuffer que el servidor pone bajo su pixmap (BuffersFromPixmap),
   escribe en él y lo presenta (PresentPixmap); la ventana muestra lo escrito. Con --pantalla-completa la ventana ocupa
   toda la pantalla y además se espera que Present la entregue por flip (sin copia).
   gcc -O2 -o /tmp/dri3-buffers dri3-buffers.c -lxcb -lxcb-dri3 -lxcb-present && /tmp/dri3-buffers  */
#include <linux/dma-buf.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <xcb/dri3.h>
#include <xcb/present.h>
#include <xcb/xcb.h>

static int fallas;

static void
caso(const char *nombre, int ok)
{
    printf("%s %s\n", ok ? "OK   " : "FALLA", nombre);
    fallas += !ok;
}

int
main(int argc, char **argv)
{
    int completa = argc > 1 && strcmp(argv[1], "--pantalla-completa") == 0;
    xcb_connection_t *c = xcb_connect(NULL, NULL);
    const uint32_t color = 0x00ff8000;  /* XRGB: naranjo */

    if (xcb_connection_has_error(c)) {
        printf("FALLA no hay conexión con el servidor X\nfallas: 1\n");
        return 1;
    }
    xcb_screen_t *pantalla = xcb_setup_roots_iterator(xcb_get_setup(c)).data;
    uint16_t w = completa ? pantalla->width_in_pixels : 64, h = completa ? pantalla->height_in_pixels : 64;
    xcb_window_t ventana = xcb_generate_id(c);
    uint32_t valores[] = { 1 };         /* override-redirect: sin gestor de ventanas ni compositor de por medio */

    xcb_create_window(c, pantalla->root_depth, ventana, pantalla->root, 0, 0, w, h, 0,
                      XCB_WINDOW_CLASS_INPUT_OUTPUT, pantalla->root_visual, XCB_CW_OVERRIDE_REDIRECT, valores);
    xcb_map_window(c, ventana);
    xcb_pixmap_t pixmap = xcb_generate_id(c);
    xcb_create_pixmap(c, pantalla->root_depth, pixmap, ventana, w, h);

    xcb_dri3_buffers_from_pixmap_reply_t *b =
        xcb_dri3_buffers_from_pixmap_reply(c, xcb_dri3_buffers_from_pixmap(c, pixmap), NULL);
    caso("BuffersFromPixmap devuelve un dmabuf", b && b->nfd == 1);
    if (!b || b->nfd != 1) {
        printf("fallas: %d\n", fallas);
        return 1;
    }
    int fd = xcb_dri3_buffers_from_pixmap_reply_fds(c, b)[0];
    uint32_t stride = xcb_dri3_buffers_from_pixmap_strides(b)[0];
    caso("el stride alcanza para una fila de 32 bpp", stride >= (uint32_t) w * 4);
    caso("el modificador es LINEAR", b->modifier == 0);

    uint32_t *mapa = mmap(NULL, (size_t) stride * h, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    caso("el dmabuf se puede mapear", mapa != MAP_FAILED);
    if (mapa == MAP_FAILED) {
        printf("fallas: %d\n", fallas);
        return 1;
    }
    struct dma_buf_sync sync = { DMA_BUF_SYNC_START | DMA_BUF_SYNC_WRITE };
    ioctl(fd, DMA_BUF_IOCTL_SYNC, &sync);
    for (int y = 0; y < h; y++)
        for (int x = 0; x < w; x++)
            mapa[(size_t) y * (stride / 4) + x] = color;
    sync.flags = DMA_BUF_SYNC_END | DMA_BUF_SYNC_WRITE;
    ioctl(fd, DMA_BUF_IOCTL_SYNC, &sync);

    xcb_present_event_t eid = xcb_generate_id(c);
    xcb_present_select_input(c, eid, ventana, XCB_PRESENT_EVENT_MASK_COMPLETE_NOTIFY);
    xcb_present_pixmap(c, ventana, pixmap, 1, 0, 0, 0, 0, 0, 0, 0, XCB_PRESENT_OPTION_NONE, 0, 0, 0, 0, NULL);
    xcb_flush(c);
    int modo = -1;
    for (xcb_generic_event_t *e; modo < 0 && (e = xcb_wait_for_event(c)); free(e)) {
        if ((e->response_type & 0x7f) == XCB_GE_GENERIC) {
            xcb_present_complete_notify_event_t *ce = (void *) e;
            if (ce->event_type == XCB_PRESENT_COMPLETE_NOTIFY && ce->kind == XCB_PRESENT_COMPLETE_KIND_PIXMAP)
                modo = ce->mode;
        }
    }
    caso("llega PresentCompleteNotify", modo >= 0);
    printf("      modo: %s\n", modo == XCB_PRESENT_COMPLETE_MODE_FLIP ? "flip" :
                               modo == XCB_PRESENT_COMPLETE_MODE_COPY ? "copia" : "otro");

    xcb_get_image_reply_t *img = xcb_get_image_reply(c, xcb_get_image(c, XCB_IMAGE_FORMAT_Z_PIXMAP, ventana,
                                                                      w / 2, h / 2, 1, 1, ~0), NULL);
    uint32_t visto = img ? *(uint32_t *) xcb_get_image_data(img) & 0xffffff : 0;
    printf("      píxel del centro: %06x (esperado %06x)\n", visto, color);
    caso("la ventana muestra lo escrito en el dmabuf", img && visto == color);
    if (completa)
        caso("a pantalla completa Present entrega por flip", modo == XCB_PRESENT_COMPLETE_MODE_FLIP);

    printf("fallas: %d\n", fallas);
    return fallas != 0;
}
