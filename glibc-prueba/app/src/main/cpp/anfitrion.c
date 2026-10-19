/* Anfitrión Wayland mínimo dentro de la app (bionic, NDK).

   Los programas glibc (sway anidado, foot...) se conectan al socket
   <prefijo>/run/user/<uid>/wayland-0 y comparten sus cuadros por memfd
   (wl_shm).  El anfitrión muestra a pantalla completa el último xdg_toplevel
   mapeado: copia el buffer a una ANativeWindow (el SurfaceView de
   WaylandActivity) y le devuelve el tacto (gestos -> puntero y scroll) y el teclado
   (códigos evdev + keymap xkb latam de keymap.h; wlroots lo ignora y usa el
   de la config de sway, los clientes directos lo usan).

   Protocolos: wl_compositor, wl_shm, zwp_linux_dmabuf_v1 (v3, solo LINEAR:
   el anfitrión lee el dmabuf por mmap), android_ahb_v1 (propio, cero copias:
   wayland/android-ahb-v1.xml), xdg_wm_base, wl_seat, wl_output.  Todo
   corre en un hilo propio (wl_display_run); lo que llega de Java pasa por una
   cola y un eventfd.  */

#define _GNU_SOURCE
#include <android/choreographer.h>
#include <android/hardware_buffer.h>
#include <android/looper.h>
#include <android/log.h>
#include <android/native_window_jni.h>
#include <android/surface_control.h>
#include <errno.h>
#include <fcntl.h>
#include <jni.h>
#include <linux/dma-buf.h>
#include <linux/input-event-codes.h>
#include <poll.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <sys/eventfd.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>
#include <wayland-server.h>

#include "android-ahb-v1-server-protocol.h"
#include "keymap.h"
#include "linux-dmabuf-v1-server-protocol.h"
#include "pointer-gestures-unstable-v1-server-protocol.h"
#include "xdg-shell-server-protocol.h"

#define LOG(...) __android_log_print (ANDROID_LOG_INFO, "WAYLAND", __VA_ARGS__)

struct superficie
{
  struct wl_resource *res;
  struct wl_resource *buffer;	/* adjuntado, pendiente de commit */
  struct wl_listener buffer_destruido;
  bool adjuntado;
  struct wl_list callbacks;	/* wl_callback pendientes */
  struct wl_resource *xdg_surface, *toplevel;
  bool configurado, mapeado;
  int buf_w, buf_h;
  struct wl_list link;		/* en toplevels */
};

static struct wl_display *display;
static struct wl_list toplevels, punteros, teclados, salidas, deslizar;
static struct superficie *foco, *foco_puntero;
static uint32_t mods;

/* Ventana Android y lo que se muestra en ella, protegidos por mtx.  La fuente
   es el cuadro (copia de un buffer wl_shm) o el último dmabuf, que se retiene
   (sin wl_buffer.release) para poder redibujar si la ventana se recrea.  */
static pthread_mutex_t mtx = PTHREAD_MUTEX_INITIALIZER;
static ANativeWindow *ventana;
static int vent_w, vent_h, mm_w, mm_h;
static uint32_t *cuadro;
static int cuadro_w, cuadro_h;
static struct
{
  const uint8_t *datos;
  int stride, w, h;
  bool bgra;	/* XRGB/ARGB de Wayland: BGRA en memoria */
  int fd;	/* dmabuf (para DMA_BUF_IOCTL_SYNC) o -1 */
} fuente = { .fd = -1 };

/* HAL_PIXEL_FORMAT_BGRA_8888: no está en el NDK, pero gralloc lo acepta para
   ventanas; evita convertir píxel a píxel los clientes XRGB/ARGB.  */
#define VENTANA_BGRA 5

/* Cola Java -> hilo del anfitrión.  */
enum { EV_VENTANA, EV_MOVER, EV_BOTON, EV_EJE, EV_GESTO, EV_TECLA, EV_TOMADA, EV_COMPLETADA, EV_VSYNC };
struct evento { int tipo, a; float x, y; void *p; };
static struct evento cola[512];
static int ncola, evfd = -1;

static uint32_t
ahora_ms (void)
{
  struct timespec t;
  clock_gettime (CLOCK_MONOTONIC, &t);
  return t.tv_sec * 1000 + t.tv_nsec / 1000000;
}

static void
destruir_recurso (struct wl_client *c, struct wl_resource *r)
{
  wl_resource_destroy (r);
}

static void
quitar_de_lista (struct wl_resource *r)
{
  wl_list_remove (wl_resource_get_link (r));
}

/* ---------- dibujo ---------- */

/* Copia la fuente a la ventana (con mtx tomado): una pasada, memcpy por fila
   si la ventana tiene el mismo orden de bytes.  */
static void
mostrar (void)
{
  if (ventana == NULL || fuente.datos == NULL)
    return;
  int formato = fuente.bgra ? VENTANA_BGRA : WINDOW_FORMAT_RGBX_8888;
  if (ANativeWindow_setBuffersGeometry (ventana, fuente.w, fuente.h, formato) != 0)
    ANativeWindow_setBuffersGeometry (ventana, fuente.w, fuente.h, WINDOW_FORMAT_RGBX_8888);
  ANativeWindow_Buffer out;
  if (ANativeWindow_lock (ventana, &out, NULL) != 0)
    return;
  bool convertir = fuente.bgra && out.format != VENTANA_BGRA;
  int w = out.width < fuente.w ? out.width : fuente.w;
  int h = out.height < fuente.h ? out.height : fuente.h;
  struct dma_buf_sync sync = { DMA_BUF_SYNC_START | DMA_BUF_SYNC_READ };
  if (fuente.fd >= 0)
    ioctl (fuente.fd, DMA_BUF_IOCTL_SYNC, &sync);
  for (int y = 0; y < h; y++)
    {
      const uint32_t *src = (const uint32_t *) (fuente.datos + (size_t) y * fuente.stride);
      uint32_t *dst = (uint32_t *) out.bits + (size_t) y * out.stride;
      if (convertir)
	for (int x = 0; x < w; x++)
	  {
	    uint32_t p = src[x];
	    dst[x] = (p & 0x0000ff00) | ((p & 0xff) << 16) | ((p >> 16) & 0xff)
		     | 0xff000000;
	  }
      else
	memcpy (dst, src, (size_t) w * 4);
    }
  if (fuente.fd >= 0)
    {
      sync.flags = DMA_BUF_SYNC_END | DMA_BUF_SYNC_READ;
      ioctl (fuente.fd, DMA_BUF_IOCTL_SYNC, &sync);
    }
  ANativeWindow_unlockAndPost (ventana);
}

/* dmabuf retenido como fuente (ver más abajo).  */
static struct wl_resource *retenido;

static void
soltar_retenido (void)
{
  if (retenido != NULL)
    wl_buffer_send_release (retenido);
  retenido = NULL;
}

/* Buffer wl_shm -> cuadro (el cliente puede reusarlo apenas se libera).  */
static void
copiar_pixeles (struct superficie *s, const uint8_t *datos, int stride, int w, int h,
		bool bgra)
{
  s->buf_w = w;
  s->buf_h = h;

  pthread_mutex_lock (&mtx);
  soltar_retenido ();
  if (cuadro == NULL || cuadro_w != w || cuadro_h != h)
    {
      free (cuadro);
      cuadro = malloc ((size_t) w * h * 4);
      cuadro_w = w;
      cuadro_h = h;
    }
  for (int y = 0; y < h; y++)
    memcpy (cuadro + (size_t) y * w, datos + (size_t) y * stride, (size_t) w * 4);
  fuente.datos = (const uint8_t *) cuadro;
  fuente.stride = w * 4;
  fuente.w = w;
  fuente.h = h;
  fuente.bgra = bgra;
  fuente.fd = -1;
  mostrar ();
  pthread_mutex_unlock (&mtx);
}

static void
copiar_shm (struct superficie *s, struct wl_shm_buffer *b)
{
  uint32_t fmt = wl_shm_buffer_get_format (b);
  bool bgra = fmt == WL_SHM_FORMAT_ARGB8888 || fmt == WL_SHM_FORMAT_XRGB8888;
  if (!bgra && fmt != WL_SHM_FORMAT_ABGR8888 && fmt != WL_SHM_FORMAT_XBGR8888)
    {
      LOG ("formato wl_shm no soportado: 0x%x", fmt);
      return;
    }
  wl_shm_buffer_begin_access (b);
  copiar_pixeles (s, wl_shm_buffer_get_data (b), wl_shm_buffer_get_stride (b),
		  wl_shm_buffer_get_width (b), wl_shm_buffer_get_height (b), bgra);
  wl_shm_buffer_end_access (b);
}

/* ---------- linux-dmabuf (v3) ----------
   Los clientes Vulkan/GL (Turnip, Zink) mandan sus imágenes como dmabuf
   (reservadas en /dev/dma_heap/system).  Solo LINEAR y un plano: el anfitrión
   espera la fence implícita (poll), lo lee por mmap y lo copia como un shm.  */

/* Códigos fourcc de DRM (drm_fourcc.h); coinciden con los de wl_shm salvo
   ARGB/XRGB, que en wl_shm son 0 y 1.  */
#define DRM_ARGB8888 0x34325241
#define DRM_XRGB8888 0x34325258
#define DRM_ABGR8888 0x34324241
#define DRM_XBGR8888 0x34324258
#define MOD_LINEAR 0ULL
#define MOD_INVALID 0x00ffffffffffffffULL

static const uint32_t formatos_dmabuf[] = {
  DRM_ARGB8888, DRM_XRGB8888, DRM_ABGR8888, DRM_XBGR8888,
};

struct dmabuf
{
  struct wl_resource *res;
  int fd;
  uint32_t formato, offset, stride;
  int32_t w, h;
  uint64_t modificador;
  void *mapa;
  size_t tam_mapa;
};

static const struct wl_buffer_interface dmabuf_buffer_impl = {
  .destroy = destruir_recurso,
};

static void
dmabuf_destruido (struct wl_resource *r)
{
  struct dmabuf *d = wl_resource_get_user_data (r);
  if (d == NULL)
    return;
  pthread_mutex_lock (&mtx);
  if (retenido == r)
    {
      retenido = NULL;
      fuente.datos = NULL;	/* la ventana conserva el último cuadro mostrado */
      fuente.fd = -1;
    }
  pthread_mutex_unlock (&mtx);
  if (d->mapa != NULL)
    munmap (d->mapa, d->tam_mapa);
  if (d->fd >= 0)
    close (d->fd);
  free (d);
}

static struct dmabuf *
dmabuf_de (struct wl_resource *buffer)
{
  if (!wl_resource_instance_of (buffer, &wl_buffer_interface, &dmabuf_buffer_impl))
    return NULL;
  return wl_resource_get_user_data (buffer);
}

/* Muestra el dmabuf leyéndolo directo (una sola copia, a la ventana) y lo
   retiene hasta que llegue otro: se libera el anterior.  */
static void
mostrar_dmabuf (struct superficie *s, struct dmabuf *d)
{
  if (d->mapa == NULL)
    {
      d->tam_mapa = (size_t) d->offset + (size_t) d->stride * d->h;
      d->mapa = mmap (NULL, d->tam_mapa, PROT_READ, MAP_SHARED, d->fd, 0);
      if (d->mapa == MAP_FAILED)
	{
	  LOG ("mmap del dmabuf: %s", strerror (errno));
	  d->mapa = NULL;
	  wl_buffer_send_release (d->res);
	  return;
	}
    }
  /* Sincronización implícita: la WSI de Mesa le pega al dmabuf la fence del
     render; POLLIN = ya se puede leer.  */
  struct pollfd pfd = { d->fd, POLLIN, 0 };
  poll (&pfd, 1, 100);
  s->buf_w = d->w;
  s->buf_h = d->h;
  pthread_mutex_lock (&mtx);
  fuente.datos = (const uint8_t *) d->mapa + d->offset;
  fuente.stride = d->stride;
  fuente.w = d->w;
  fuente.h = d->h;
  fuente.bgra = d->formato == DRM_ARGB8888 || d->formato == DRM_XRGB8888;
  fuente.fd = d->fd;
  mostrar ();
  if (retenido != d->res)
    soltar_retenido ();
  retenido = d->res;
  pthread_mutex_unlock (&mtx);
}

/* zwp_linux_buffer_params_v1: junta el plano 0 y arma el wl_buffer.  */
static void
params_add (struct wl_client *c, struct wl_resource *r, int32_t fd, uint32_t plano,
	    uint32_t offset, uint32_t stride, uint32_t mod_hi, uint32_t mod_lo)
{
  struct dmabuf *d = wl_resource_get_user_data (r);
  if (d == NULL)
    {
      close (fd);
      wl_resource_post_error (r, ZWP_LINUX_BUFFER_PARAMS_V1_ERROR_ALREADY_USED,
			      "params ya usados");
      return;
    }
  if (plano != 0 || d->fd >= 0)
    {
      close (fd);
      wl_resource_post_error (r, ZWP_LINUX_BUFFER_PARAMS_V1_ERROR_PLANE_IDX,
			      "solo se admite un plano");
      return;
    }
  d->fd = fd;
  d->offset = offset;
  d->stride = stride;
  d->modificador = ((uint64_t) mod_hi << 32) | mod_lo;
}

static struct wl_resource *
params_crear_buffer (struct wl_client *c, struct wl_resource *r, uint32_t id,
		     int32_t w, int32_t h, uint32_t formato)
{
  struct dmabuf *d = wl_resource_get_user_data (r);
  if (d == NULL)
    {
      wl_resource_post_error (r, ZWP_LINUX_BUFFER_PARAMS_V1_ERROR_ALREADY_USED,
			      "params ya usados");
      return NULL;
    }
  wl_resource_set_user_data (r, NULL);
  bool formato_ok = false;
  for (size_t i = 0; i < sizeof formatos_dmabuf / sizeof *formatos_dmabuf; i++)
    formato_ok |= formatos_dmabuf[i] == formato;
  if (d->fd < 0 || w <= 0 || h <= 0 || d->stride < (uint32_t) w * 4 || !formato_ok
      || (d->modificador != MOD_LINEAR && d->modificador != MOD_INVALID))
    {
      LOG ("dmabuf rechazado: %dx%d formato 0x%x stride %u modificador 0x%llx",
	   w, h, formato, d->stride, (unsigned long long) d->modificador);
      if (d->fd >= 0)
	close (d->fd);
      free (d);
      return NULL;
    }
  d->w = w;
  d->h = h;
  d->formato = formato;
  struct wl_resource *b = wl_resource_create (c, &wl_buffer_interface, 1, id);
  if (b == NULL)
    {
      close (d->fd);
      free (d);
      wl_client_post_no_memory (c);
      return NULL;
    }
  d->res = b;
  wl_resource_set_implementation (b, &dmabuf_buffer_impl, d, dmabuf_destruido);
  return b;
}

static void
params_create (struct wl_client *c, struct wl_resource *r, int32_t w, int32_t h,
	       uint32_t formato, uint32_t flags)
{
  struct wl_resource *b = params_crear_buffer (c, r, 0, w, h, formato);
  if (b != NULL)
    zwp_linux_buffer_params_v1_send_created (r, b);
  else
    zwp_linux_buffer_params_v1_send_failed (r);
}

static void
params_create_immed (struct wl_client *c, struct wl_resource *r, uint32_t id,
		     int32_t w, int32_t h, uint32_t formato, uint32_t flags)
{
  if (params_crear_buffer (c, r, id, w, h, formato) == NULL)
    wl_resource_post_error (r, ZWP_LINUX_BUFFER_PARAMS_V1_ERROR_INVALID_WL_BUFFER,
			    "dmabuf no admitido");
}

static const struct zwp_linux_buffer_params_v1_interface params_impl = {
  .destroy = destruir_recurso,
  .add = params_add,
  .create = params_create,
  .create_immed = params_create_immed,
};

static void
params_destruidos (struct wl_resource *r)
{
  struct dmabuf *d = wl_resource_get_user_data (r);
  if (d == NULL)
    return;
  if (d->fd >= 0)
    close (d->fd);
  free (d);
}

static void
dmabuf_create_params (struct wl_client *c, struct wl_resource *r, uint32_t id)
{
  struct dmabuf *d = calloc (1, sizeof *d);
  struct wl_resource *p = wl_resource_create (c, &zwp_linux_buffer_params_v1_interface,
					      wl_resource_get_version (r), id);
  if (d == NULL || p == NULL)
    {
      free (d);
      wl_client_post_no_memory (c);
      return;
    }
  d->fd = -1;
  wl_resource_set_implementation (p, &params_impl, d, params_destruidos);
}

static const struct zwp_linux_dmabuf_v1_interface linux_dmabuf_impl = {
  .destroy = destruir_recurso,
  .create_params = dmabuf_create_params,
};

static void
linux_dmabuf_bind (struct wl_client *c, void *data, uint32_t version, uint32_t id)
{
  struct wl_resource *r = wl_resource_create (c, &zwp_linux_dmabuf_v1_interface, version, id);
  if (r == NULL)
    {
      wl_client_post_no_memory (c);
      return;
    }
  wl_resource_set_implementation (r, &linux_dmabuf_impl, NULL, NULL);
  for (size_t i = 0; i < sizeof formatos_dmabuf / sizeof *formatos_dmabuf; i++)
    {
      zwp_linux_dmabuf_v1_send_format (r, formatos_dmabuf[i]);
      if (version >= ZWP_LINUX_DMABUF_V1_MODIFIER_SINCE_VERSION)
	zwp_linux_dmabuf_v1_send_modifier (r, formatos_dmabuf[i], MOD_LINEAR >> 32,
					   MOD_LINEAR & 0xffffffff);
    }
}

/* ---------- android-ahb-v1: cero copias ----------
   El cliente pide un wl_buffer y el anfitrión reserva un AHardwareBuffer;
   le devuelve su dmabuf (gralloc), el cliente dibuja ahí con la GPU y al hacer
   commit el AHardwareBuffer va tal cual a SurfaceFlinger, en una capa hija
   (ASurfaceControl) del SurfaceView.  Nadie toca los píxeles con la CPU.
   Sincronización implícita en el dmabuf: la fence del render (que la WSI le
   pega) es la acquire fence de SurfaceFlinger, y su release fence se le pega al
   dmabuf antes de mandar wl_buffer.release.  Los frame callbacks se responden
   en el primer vsync (AChoreographer) después de que SurfaceFlinger tomó la
   transacción (OnCommit): con OnComplete el cliente iba a la mitad de la
   frecuencia, y con OnCommit solo, sin freno (SurfaceFlinger descarta cuadros).  */

struct ahb
{
  struct wl_resource *res;	/* NULL si el cliente ya lo destruyó */
  AHardwareBuffer *ahb;
  int fd;			/* dmabuf del AHardwareBuffer */
  int w, h, refs;		/* refs: el recurso + cada transacción que lo nombra */
};

/* Una transacción en vuelo; al completarse vuelve al hilo del anfitrión.  */
struct transaccion
{
  ASurfaceControl *capa;
  struct ahb *anterior;		/* el que reemplaza: se libera con la release fence */
  struct wl_list callbacks;	/* frame callbacks de este cuadro */
  int fence;
};

/* capa = hija del SurfaceView, en_pantalla = lo que muestra.  Protegidos por
   mtx; en_pantalla solo se escribe en el hilo del anfitrión.  */
static ASurfaceControl *capa;
static struct ahb *en_pantalla;
static int ahb_vistos;

static void
ahb_soltar_ref (struct ahb *b)
{
  if (b == NULL || --b->refs > 0)
    return;
  AHardwareBuffer_release (b->ahb);
  close (b->fd);
  free (b);
}

static const struct wl_buffer_interface ahb_buffer_impl = {
  .destroy = destruir_recurso,
};

static void
ahb_destruido (struct wl_resource *r)
{
  struct ahb *b = wl_resource_get_user_data (r);
  if (b == NULL)	/* falló la reserva */
    return;
  b->res = NULL;
  ahb_soltar_ref (b);
}

static struct ahb *
ahb_de (struct wl_resource *buffer)
{
  if (!wl_resource_instance_of (buffer, &wl_buffer_interface, &ahb_buffer_impl))
    return NULL;
  return wl_resource_get_user_data (buffer);
}

/* El dmabuf de un AHardwareBuffer: la API pública solo lo entrega serializado
   por un socket (como GraphicBuffer::flatten: 13 enteros de cabecera y luego
   los del native_handle; los fd van aparte).  Con gralloc de Qualcomm el
   primer fd es el buffer y el segundo, los metadatos.  */
static int
fd_de_ahb (AHardwareBuffer *ahb)
{
  int sv[2];
  if (socketpair (AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0, sv) != 0)
    return -1;
  int fd = -1;
  if (AHardwareBuffer_sendHandleToUnixSocket (ahb, sv[0]) == 0)
    {
      uint32_t datos[256];
      char control[CMSG_SPACE (16 * sizeof (int))];
      struct iovec iov = { datos, sizeof datos };
      struct msghdr msg = { .msg_iov = &iov, .msg_iovlen = 1,
			    .msg_control = control, .msg_controllen = sizeof control };
      ssize_t n = recvmsg (sv[1], &msg, MSG_CMSG_CLOEXEC);
      struct cmsghdr *cm = n > 0 ? CMSG_FIRSTHDR (&msg) : NULL;
      if (cm != NULL && cm->cmsg_type == SCM_RIGHTS)
	{
	  int nfds = (cm->cmsg_len - CMSG_LEN (0)) / sizeof (int);
	  int *fds = (int *) CMSG_DATA (cm);
	  fd = fds[0];
	  for (int i = 1; i < nfds; i++)
	    close (fds[i]);
	  if (ahb_vistos++ == 0 && n >= 13 * 4)
	    {
	      /* Primera vez: mostrar el handle para saber cómo es (UBWC, offset).  */
	      char linea[512];
	      int len = 0, nints = datos[11];
	      for (int i = 0; i < nints && 13 + i < n / 4 && len < 480; i++)
		len += snprintf (linea + len, sizeof linea - len, " %x", datos[13 + i]);
	      LOG ("AHardwareBuffer: %dx%d stride %d formato %d, %d fd, ints:%s",
		   datos[1], datos[2], datos[3], datos[4], nfds, linea);
	    }
	}
    }
  close (sv[0]);
  close (sv[1]);
  return fd;
}

static void
ahb_crear (struct wl_client *c, struct wl_resource *r, uint32_t id,
	   int32_t w, int32_t h, uint32_t formato)
{
  struct wl_resource *res = wl_resource_create (c, &wl_buffer_interface, 1, id);
  if (res == NULL)
    {
      wl_client_post_no_memory (c);
      return;
    }
  wl_resource_set_implementation (res, &ahb_buffer_impl, NULL, ahb_destruido);

  AHardwareBuffer_Desc desc = {
    .width = w, .height = h, .layers = 1,
    .usage = AHARDWAREBUFFER_USAGE_GPU_COLOR_OUTPUT
	     | AHARDWAREBUFFER_USAGE_GPU_SAMPLED_IMAGE
	     | AHARDWAREBUFFER_USAGE_COMPOSER_OVERLAY,
  };
  switch (formato)
    {
    case DRM_ABGR8888: desc.format = AHARDWAREBUFFER_FORMAT_R8G8B8A8_UNORM; break;
    case DRM_XBGR8888: desc.format = AHARDWAREBUFFER_FORMAT_R8G8B8X8_UNORM; break;
    case DRM_ARGB8888: case DRM_XRGB8888: desc.format = VENTANA_BGRA; break;
    }
  AHardwareBuffer *ahb = NULL;
  int fd = -1;
  if (w <= 0 || h <= 0 || w > 8192 || h > 8192 || desc.format == 0
      || AHardwareBuffer_allocate (&desc, &ahb) != 0
      || (fd = fd_de_ahb (ahb)) < 0)
    {
      LOG ("AHardwareBuffer %dx%d formato 0x%x: no se pudo reservar", w, h, formato);
      if (ahb != NULL)
	AHardwareBuffer_release (ahb);
      android_ahb_v1_send_fallo (r, res);
      return;
    }
  AHardwareBuffer_describe (ahb, &desc);
  struct ahb *b = calloc (1, sizeof *b);
  b->res = res;
  b->ahb = ahb;
  b->fd = fd;
  b->w = w;
  b->h = h;
  b->refs = 1;
  wl_resource_set_user_data (res, b);
  android_ahb_v1_send_listo (r, res, fd, 0, desc.stride * 4);
}

static const struct android_ahb_v1_interface android_ahb_impl = {
  .destroy = destruir_recurso,
  .crear = ahb_crear,
};

static void
android_ahb_bind (struct wl_client *c, void *data, uint32_t version, uint32_t id)
{
  struct wl_resource *r = wl_resource_create (c, &android_ahb_v1_interface, version, id);
  if (r == NULL)
    {
      wl_client_post_no_memory (c);
      return;
    }
  wl_resource_set_implementation (r, &android_ahb_impl, NULL, NULL);
}

/* Hilo de binder de SurfaceFlinger: solo junta la release fence y lo pasa a la
   cola (el resto, en el hilo del anfitrión).  */
static void encolar_transaccion (int tipo, struct transaccion *t);

static void
transaccion_tomada (void *ctx, ASurfaceTransactionStats *stats)
{
  encolar_transaccion (EV_TOMADA, ctx);
}

static void
transaccion_completada (void *ctx, ASurfaceTransactionStats *stats)
{
  struct transaccion *t = ctx;
  t->fence = t->anterior != NULL
	     ? ASurfaceTransactionStats_getPreviousReleaseFenceFd (stats, t->capa) : -1;
  encolar_transaccion (EV_COMPLETADA, t);
}

/* Frame callbacks de transacciones ya tomadas, esperando el próximo vsync.  */
static struct wl_list para_vsync;
static void pedir_vsync (void);

/* Sin ventana (app en segundo plano) los frame callbacks esperan a que vuelva:
   respondidos al tiro, sway y sus clientes dibujaban sin freno (~50 % de un
   núcleo con vkcube).  Hilo del anfitrión.  */
static struct wl_list sin_ventana;

static void
guardar_sin_ventana (struct wl_list *cbs)
{
  wl_list_insert_list (sin_ventana.prev, cbs);
  wl_list_init (cbs);
}

static void
responder_callbacks (struct wl_list *cbs)
{
  uint32_t ms = ahora_ms ();
  struct wl_resource *cb, *tmp;
  wl_resource_for_each_safe (cb, tmp, cbs)
    {
      wl_callback_send_done (cb, ms);
      wl_resource_destroy (cb);
    }
}

/* OnCommit llega siempre antes que OnComplete (misma cola).  */
static void
tomada (struct transaccion *t)
{
  if (wl_list_empty (&t->callbacks))
    return;
  wl_list_insert_list (para_vsync.prev, &t->callbacks);
  wl_list_init (&t->callbacks);
  pedir_vsync ();
}

static void
completada (struct transaccion *t)
{
  responder_callbacks (&t->callbacks);	/* sin capa no hubo OnCommit */
  struct ahb *b = t->anterior;
  if (b != NULL)
    {
      if (t->fence >= 0)
	{
	  struct dma_buf_import_sync_file imp = { DMA_BUF_SYNC_READ, t->fence };
	  if (ioctl (b->fd, DMA_BUF_IOCTL_IMPORT_SYNC_FILE, &imp) != 0)
	    {
	      struct pollfd pfd = { t->fence, POLLIN, 0 };	/* sin dma_resv: esperar */
	      poll (&pfd, 1, 100);
	    }
	  close (t->fence);
	}
      /* en_pantalla solo cambia en este hilo.  */
      if (b->res != NULL && b != en_pantalla)
	wl_buffer_send_release (b->res);
      ahb_soltar_ref (b);
    }
  if (t->capa != NULL)
    ASurfaceControl_release (t->capa);
  free (t);
}

/* Estira b a w×h.  Recorte, posición y escala explícitos en cada transacción:
   con setGeometry, SurfaceFlinger se quedaba con la escala del primer buffer
   (sway manda uno de 1280×720 antes del configure) aunque cambiara el tamaño.  */
static void
geometria (ASurfaceTransaction *tr, ASurfaceControl *capa, struct ahb *b, int w, int h)
{
  ASurfaceTransaction_setCrop (tr, capa, &(ARect) { 0, 0, b->w, b->h });
  ASurfaceTransaction_setPosition (tr, capa, 0, 0);
  ASurfaceTransaction_setScale (tr, capa, (float) w / b->w, (float) h / b->h);
}

/* Muestra b en la capa (NULL: la oculta, para volver al SurfaceView).  Los
   frame callbacks de cbs se responden al completarse.  */
static void
presentar (struct ahb *b, struct wl_list *cbs)
{
  struct transaccion *t = calloc (1, sizeof *t);
  wl_list_init (&t->callbacks);
  t->fence = -1;
  if (cbs != NULL)
    {
      wl_list_insert_list (&t->callbacks, cbs);
      wl_list_init (cbs);
    }
  pthread_mutex_lock (&mtx);
  if (b != en_pantalla)
    {
      t->anterior = en_pantalla;	/* su referencia pasa a la transacción */
      en_pantalla = b;
      if (b != NULL)
	b->refs++;
    }
  if (capa == NULL)
    {
      /* Sin ventana no hay nada que mostrar: se completa al tiro.  */
      pthread_mutex_unlock (&mtx);
      guardar_sin_ventana (&t->callbacks);
      completada (t);
      return;
    }
  ASurfaceControl_acquire (capa);
  t->capa = capa;
  ASurfaceTransaction *tr = ASurfaceTransaction_create ();
  if (b != NULL)
    {
      /* Acquire fence: la del render que la WSI le pegó al dmabuf.  */
      struct dma_buf_export_sync_file exp = { DMA_BUF_SYNC_READ, -1 };
      int fence = ioctl (b->fd, DMA_BUF_IOCTL_EXPORT_SYNC_FILE, &exp) == 0 ? exp.fd : -1;
      ASurfaceTransaction_setBuffer (tr, capa, b->ahb, fence);
      geometria (tr, capa, b, vent_w, vent_h);
      ASurfaceTransaction_setBufferTransparency (tr, capa, ASURFACE_TRANSACTION_TRANSPARENCY_OPAQUE);
      ASurfaceTransaction_setVisibility (tr, capa, ASURFACE_TRANSACTION_VISIBILITY_SHOW);
    }
  else
    ASurfaceTransaction_setVisibility (tr, capa, ASURFACE_TRANSACTION_VISIBILITY_HIDE);
  ASurfaceTransaction_setOnCommit (tr, t, transaccion_tomada);
  ASurfaceTransaction_setOnComplete (tr, t, transaccion_completada);
  ASurfaceTransaction_apply (tr);
  ASurfaceTransaction_delete (tr);
  pthread_mutex_unlock (&mtx);
}

/* Cambio de camino (shm/dmabuf por CPU <-> capa): uno oculta al otro.  */
static void
ocultar_capa (void)
{
  if (en_pantalla != NULL)
    presentar (NULL, NULL);
}

static void
liberar_cpu (void)
{
  pthread_mutex_lock (&mtx);
  soltar_retenido ();
  fuente.datos = NULL;
  fuente.fd = -1;
  pthread_mutex_unlock (&mtx);
}

/* ---------- foco ---------- */

static void
enviar_modificadores (struct wl_resource *k)
{
  wl_keyboard_send_modifiers (k, wl_display_next_serial (display), mods, 0, 0, 0);
}

static void
cambiar_foco (struct superficie *s)
{
  if (foco == s)
    return;
  struct wl_resource *r;
  if (foco != NULL)
    wl_resource_for_each (r, &teclados)
      if (wl_resource_get_client (r) == wl_resource_get_client (foco->res))
	wl_keyboard_send_leave (r, wl_display_next_serial (display), foco->res);
  foco = s;
  if (s == NULL)
    return;
  struct wl_array teclas;
  wl_array_init (&teclas);
  wl_resource_for_each (r, &teclados)
    if (wl_resource_get_client (r) == wl_resource_get_client (s->res))
      {
	wl_keyboard_send_enter (r, wl_display_next_serial (display), s->res, &teclas);
	enviar_modificadores (r);
      }
  wl_array_release (&teclas);
}

/* El último toplevel mapeado que quede.  */
static void
elegir_foco (void)
{
  struct superficie *s, *elegida = NULL;
  wl_list_for_each (s, &toplevels, link)
    if (s->mapeado)
      elegida = s;
  if (foco_puntero != NULL && foco_puntero != elegida)
    foco_puntero = NULL;
  cambiar_foco (elegida);
}

static void
enviar_configure (struct superficie *s)
{
  if (s->toplevel == NULL || s->xdg_surface == NULL)
    return;
  struct wl_array estados;
  wl_array_init (&estados);
  uint32_t *e = wl_array_add (&estados, 2 * sizeof (uint32_t));
  e[0] = XDG_TOPLEVEL_STATE_ACTIVATED;
  e[1] = XDG_TOPLEVEL_STATE_FULLSCREEN;
  pthread_mutex_lock (&mtx);
  int w = vent_w, h = vent_h;
  pthread_mutex_unlock (&mtx);
  xdg_toplevel_send_configure (s->toplevel, w, h, &estados);
  xdg_surface_send_configure (s->xdg_surface, wl_display_next_serial (display));
  wl_array_release (&estados);
  s->configurado = true;
}

/* ---------- wl_surface ---------- */

static void
buffer_destruido (struct wl_listener *l, void *data)
{
  struct superficie *s = wl_container_of (l, s, buffer_destruido);
  s->buffer = NULL;
  wl_list_remove (&l->link);
  wl_list_init (&l->link);
}

static void
surface_attach (struct wl_client *c, struct wl_resource *r,
		struct wl_resource *buffer, int32_t x, int32_t y)
{
  struct superficie *s = wl_resource_get_user_data (r);
  wl_list_remove (&s->buffer_destruido.link);
  wl_list_init (&s->buffer_destruido.link);
  s->buffer = buffer;
  s->adjuntado = true;
  if (buffer != NULL)
    wl_resource_add_destroy_listener (buffer, &s->buffer_destruido);
}

static void
surface_damage (struct wl_client *c, struct wl_resource *r,
		int32_t x, int32_t y, int32_t w, int32_t h)
{
}

static void
surface_frame (struct wl_client *c, struct wl_resource *r, uint32_t id)
{
  struct superficie *s = wl_resource_get_user_data (r);
  struct wl_resource *cb = wl_resource_create (c, &wl_callback_interface, 1, id);
  if (cb == NULL)
    {
      wl_client_post_no_memory (c);
      return;
    }
  wl_resource_set_implementation (cb, NULL, NULL, quitar_de_lista);
  wl_list_insert (s->callbacks.prev, wl_resource_get_link (cb));
}

static void
surface_region (struct wl_client *c, struct wl_resource *r,
		struct wl_resource *region)
{
}

static void
surface_commit (struct wl_client *c, struct wl_resource *r)
{
  struct superficie *s = wl_resource_get_user_data (r);
  if (s->adjuntado)
    {
      s->adjuntado = false;
      struct wl_resource *buffer = s->buffer;
      wl_list_remove (&s->buffer_destruido.link);
      wl_list_init (&s->buffer_destruido.link);
      s->buffer = NULL;
      if (buffer == NULL)
	{
	  if (s->mapeado)
	    {
	      s->mapeado = false;
	      elegir_foco ();
	    }
	}
      else
	{
	  struct wl_shm_buffer *shm = wl_shm_buffer_get (buffer);
	  if (s->toplevel != NULL && s->configurado && !s->mapeado)
	    {
	      s->mapeado = true;
	      wl_list_remove (&s->link);
	      wl_list_insert (toplevels.prev, &s->link);
	      elegir_foco ();
	      /* El backend wayland de wlroots ignora el tamaño del configure que
		 llega mientras activa la salida: sin otro, sway se quedaba en
		 1280×720 (estirado) hasta que la ventana cambiara de tamaño.  */
	      enviar_configure (s);
	    }
	  struct dmabuf *dmabuf = shm == NULL ? dmabuf_de (buffer) : NULL;
	  struct ahb *ahb = shm == NULL && dmabuf == NULL ? ahb_de (buffer) : NULL;
	  if (ahb != NULL && s == foco)
	    {
	      /* Lo libera SurfaceFlinger; los frame callbacks, al mostrarse.  */
	      s->buf_w = ahb->w;
	      s->buf_h = ahb->h;
	      liberar_cpu ();
	      presentar (ahb, &s->callbacks);
	      return;
	    }
	  if (shm != NULL && s == foco)
	    {
	      ocultar_capa ();
	      copiar_shm (s, shm);
	    }
	  if (dmabuf != NULL && s == foco)
	    {
	      ocultar_capa ();
	      mostrar_dmabuf (s, dmabuf);	/* lo libera al llegar el siguiente */
	    }
	  else
	    wl_buffer_send_release (buffer);
	}
    }
  else if (s->toplevel != NULL && !s->configurado)
    enviar_configure (s);	/* commit inicial, sin buffer */

  pthread_mutex_lock (&mtx);
  bool hay_ventana = ventana != NULL;
  pthread_mutex_unlock (&mtx);
  if (!hay_ventana)
    {
      guardar_sin_ventana (&s->callbacks);
      return;
    }
  uint32_t t = ahora_ms ();
  struct wl_resource *cb, *tmp;
  wl_resource_for_each_safe (cb, tmp, &s->callbacks)
    {
      wl_callback_send_done (cb, t);
      wl_resource_destroy (cb);
    }
}

static void
surface_set_int (struct wl_client *c, struct wl_resource *r, int32_t v)
{
}

static void
surface_offset (struct wl_client *c, struct wl_resource *r, int32_t x, int32_t y)
{
}

static const struct wl_surface_interface surface_impl = {
  .destroy = destruir_recurso,
  .attach = surface_attach,
  .damage = surface_damage,
  .frame = surface_frame,
  .set_opaque_region = surface_region,
  .set_input_region = surface_region,
  .commit = surface_commit,
  .set_buffer_transform = surface_set_int,
  .set_buffer_scale = surface_set_int,
  .damage_buffer = surface_damage,
  .offset = surface_offset,
};

static void
surface_destruida (struct wl_resource *r)
{
  struct superficie *s = wl_resource_get_user_data (r);
  struct wl_resource *cb, *tmp;
  wl_resource_for_each_safe (cb, tmp, &s->callbacks)
    wl_resource_destroy (cb);
  wl_list_remove (&s->buffer_destruido.link);
  wl_list_remove (&s->link);
  if (s->xdg_surface != NULL)
    wl_resource_set_user_data (s->xdg_surface, NULL);
  if (s->toplevel != NULL)
    wl_resource_set_user_data (s->toplevel, NULL);
  if (foco_puntero == s)
    foco_puntero = NULL;
  if (foco == s)
    foco = NULL;
  free (s);
  elegir_foco ();
}

/* ---------- wl_compositor / wl_region ---------- */

static void
region_rect (struct wl_client *c, struct wl_resource *r,
	     int32_t x, int32_t y, int32_t w, int32_t h)
{
}

static const struct wl_region_interface region_impl = {
  .destroy = destruir_recurso,
  .add = region_rect,
  .subtract = region_rect,
};

static void
compositor_create_surface (struct wl_client *c, struct wl_resource *r, uint32_t id)
{
  struct superficie *s = calloc (1, sizeof *s);
  s->res = wl_resource_create (c, &wl_surface_interface,
			       wl_resource_get_version (r), id);
  if (s->res == NULL)
    {
      free (s);
      wl_client_post_no_memory (c);
      return;
    }
  wl_list_init (&s->callbacks);
  wl_list_init (&s->link);
  wl_list_init (&s->buffer_destruido.link);
  s->buffer_destruido.notify = buffer_destruido;
  wl_resource_set_implementation (s->res, &surface_impl, s, surface_destruida);
}

static void
compositor_create_region (struct wl_client *c, struct wl_resource *r, uint32_t id)
{
  struct wl_resource *reg = wl_resource_create (c, &wl_region_interface, 1, id);
  if (reg == NULL)
    wl_client_post_no_memory (c);
  else
    wl_resource_set_implementation (reg, &region_impl, NULL, NULL);
}

static const struct wl_compositor_interface compositor_impl = {
  .create_surface = compositor_create_surface,
  .create_region = compositor_create_region,
};

static void
compositor_bind (struct wl_client *c, void *data, uint32_t version, uint32_t id)
{
  struct wl_resource *r = wl_resource_create (c, &wl_compositor_interface, version, id);
  wl_resource_set_implementation (r, &compositor_impl, NULL, NULL);
}

/* ---------- xdg_shell ---------- */

static void pos_set_size (struct wl_client *c, struct wl_resource *r, int32_t w, int32_t h) { }
static void pos_set_rect (struct wl_client *c, struct wl_resource *r, int32_t x, int32_t y, int32_t w, int32_t h) { }
static void pos_set_u (struct wl_client *c, struct wl_resource *r, uint32_t v) { }
static void pos_set_offset (struct wl_client *c, struct wl_resource *r, int32_t x, int32_t y) { }
static void pos_set_reactive (struct wl_client *c, struct wl_resource *r) { }
static void pos_set_parent_configure (struct wl_client *c, struct wl_resource *r, uint32_t s) { }

static const struct xdg_positioner_interface positioner_impl = {
  .destroy = destruir_recurso,
  .set_size = pos_set_size,
  .set_anchor_rect = pos_set_rect,
  .set_anchor = pos_set_u,
  .set_gravity = pos_set_u,
  .set_constraint_adjustment = pos_set_u,
  .set_offset = pos_set_offset,
  .set_reactive = pos_set_reactive,
  .set_parent_size = pos_set_size,
  .set_parent_configure = pos_set_parent_configure,
};

static void popup_grab (struct wl_client *c, struct wl_resource *r, struct wl_resource *seat, uint32_t serial) { }

static const struct xdg_popup_interface popup_impl = {
  .destroy = destruir_recurso,
  .grab = popup_grab,
};

static void tl_set_parent (struct wl_client *c, struct wl_resource *r, struct wl_resource *p) { }
static void tl_set_str (struct wl_client *c, struct wl_resource *r, const char *s) { }
static void tl_menu (struct wl_client *c, struct wl_resource *r, struct wl_resource *seat, uint32_t serial, int32_t x, int32_t y) { }
static void tl_move (struct wl_client *c, struct wl_resource *r, struct wl_resource *seat, uint32_t serial) { }
static void tl_resize (struct wl_client *c, struct wl_resource *r, struct wl_resource *seat, uint32_t serial, uint32_t edges) { }
static void tl_size (struct wl_client *c, struct wl_resource *r, int32_t w, int32_t h) { }
static void tl_nada (struct wl_client *c, struct wl_resource *r) { }
static void tl_fullscreen (struct wl_client *c, struct wl_resource *r, struct wl_resource *out) { }

static const struct xdg_toplevel_interface toplevel_impl = {
  .destroy = destruir_recurso,
  .set_parent = tl_set_parent,
  .set_title = tl_set_str,
  .set_app_id = tl_set_str,
  .show_window_menu = tl_menu,
  .move = tl_move,
  .resize = tl_resize,
  .set_max_size = tl_size,
  .set_min_size = tl_size,
  .set_maximized = tl_nada,
  .unset_maximized = tl_nada,
  .set_fullscreen = tl_fullscreen,
  .unset_fullscreen = tl_nada,
  .set_minimized = tl_nada,
};

static void
toplevel_destruido (struct wl_resource *r)
{
  struct superficie *s = wl_resource_get_user_data (r);
  if (s == NULL)
    return;
  s->toplevel = NULL;
  s->mapeado = false;
  s->configurado = false;
  wl_list_remove (&s->link);
  wl_list_init (&s->link);
  elegir_foco ();
}

static void
xdg_surface_destruida (struct wl_resource *r)
{
  struct superficie *s = wl_resource_get_user_data (r);
  if (s != NULL)
    s->xdg_surface = NULL;
}

static void
xs_get_toplevel (struct wl_client *c, struct wl_resource *r, uint32_t id)
{
  struct superficie *s = wl_resource_get_user_data (r);
  struct wl_resource *t = wl_resource_create (c, &xdg_toplevel_interface,
					      wl_resource_get_version (r), id);
  if (t == NULL)
    {
      wl_client_post_no_memory (c);
      return;
    }
  wl_resource_set_implementation (t, &toplevel_impl, s, toplevel_destruido);
  if (s == NULL)
    return;
  s->toplevel = t;
  wl_list_remove (&s->link);
  wl_list_insert (toplevels.prev, &s->link);
}

static void
xs_get_popup (struct wl_client *c, struct wl_resource *r, uint32_t id,
	      struct wl_resource *parent, struct wl_resource *positioner)
{
  /* Sin popups por ahora: se cierran apenas se piden.  */
  struct wl_resource *p = wl_resource_create (c, &xdg_popup_interface,
					      wl_resource_get_version (r), id);
  if (p == NULL)
    {
      wl_client_post_no_memory (c);
      return;
    }
  wl_resource_set_implementation (p, &popup_impl, NULL, NULL);
  xdg_popup_send_popup_done (p);
}

static void
xs_set_geometry (struct wl_client *c, struct wl_resource *r,
		 int32_t x, int32_t y, int32_t w, int32_t h)
{
}

static void
xs_ack (struct wl_client *c, struct wl_resource *r, uint32_t serial)
{
}

static const struct xdg_surface_interface xdg_surface_impl = {
  .destroy = destruir_recurso,
  .get_toplevel = xs_get_toplevel,
  .get_popup = xs_get_popup,
  .set_window_geometry = xs_set_geometry,
  .ack_configure = xs_ack,
};

static void
wm_create_positioner (struct wl_client *c, struct wl_resource *r, uint32_t id)
{
  struct wl_resource *p = wl_resource_create (c, &xdg_positioner_interface,
					      wl_resource_get_version (r), id);
  if (p == NULL)
    wl_client_post_no_memory (c);
  else
    wl_resource_set_implementation (p, &positioner_impl, NULL, NULL);
}

static void
wm_get_xdg_surface (struct wl_client *c, struct wl_resource *r, uint32_t id,
		    struct wl_resource *surface)
{
  struct superficie *s = wl_resource_get_user_data (surface);
  struct wl_resource *x = wl_resource_create (c, &xdg_surface_interface,
					      wl_resource_get_version (r), id);
  if (x == NULL)
    {
      wl_client_post_no_memory (c);
      return;
    }
  wl_resource_set_implementation (x, &xdg_surface_impl, s, xdg_surface_destruida);
  s->xdg_surface = x;
}

static void
wm_pong (struct wl_client *c, struct wl_resource *r, uint32_t serial)
{
}

static const struct xdg_wm_base_interface wm_base_impl = {
  .destroy = destruir_recurso,
  .create_positioner = wm_create_positioner,
  .get_xdg_surface = wm_get_xdg_surface,
  .pong = wm_pong,
};

static void
wm_base_bind (struct wl_client *c, void *data, uint32_t version, uint32_t id)
{
  struct wl_resource *r = wl_resource_create (c, &xdg_wm_base_interface, version, id);
  wl_resource_set_implementation (r, &wm_base_impl, NULL, NULL);
}

/* ---------- wl_seat ---------- */

static void
pointer_set_cursor (struct wl_client *c, struct wl_resource *r, uint32_t serial,
		    struct wl_resource *surface, int32_t x, int32_t y)
{
}

static const struct wl_pointer_interface pointer_impl = {
  .set_cursor = pointer_set_cursor,
  .release = destruir_recurso,
};

static const struct wl_keyboard_interface keyboard_impl = {
  .release = destruir_recurso,
};

static const struct wl_touch_interface touch_impl = {
  .release = destruir_recurso,
};

static void
seat_get_pointer (struct wl_client *c, struct wl_resource *r, uint32_t id)
{
  struct wl_resource *p = wl_resource_create (c, &wl_pointer_interface,
					      wl_resource_get_version (r), id);
  if (p == NULL)
    {
      wl_client_post_no_memory (c);
      return;
    }
  wl_resource_set_implementation (p, &pointer_impl, NULL, quitar_de_lista);
  wl_list_insert (&punteros, wl_resource_get_link (p));
}

static void
seat_get_keyboard (struct wl_client *c, struct wl_resource *r, uint32_t id)
{
  struct wl_resource *k = wl_resource_create (c, &wl_keyboard_interface,
					      wl_resource_get_version (r), id);
  if (k == NULL)
    {
      wl_client_post_no_memory (c);
      return;
    }
  wl_resource_set_implementation (k, &keyboard_impl, NULL, quitar_de_lista);
  wl_list_insert (&teclados, wl_resource_get_link (k));
  /* El keymap va en un memfd sellado: el cliente lo mapea de solo lectura.  */
  int fd = memfd_create ("keymap", MFD_CLOEXEC | MFD_ALLOW_SEALING);
  if (fd >= 0 && write (fd, keymap_xkb, sizeof keymap_xkb) == sizeof keymap_xkb)
    {
      fcntl (fd, F_ADD_SEALS, F_SEAL_SHRINK | F_SEAL_GROW | F_SEAL_WRITE | F_SEAL_SEAL);
      wl_keyboard_send_keymap (k, WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1, fd, sizeof keymap_xkb);
    }
  else
    LOG ("no se pudo armar el keymap");
  if (fd >= 0)
    close (fd);
  if (wl_resource_get_version (k) >= WL_KEYBOARD_REPEAT_INFO_SINCE_VERSION)
    wl_keyboard_send_repeat_info (k, 25, 600);
  if (foco != NULL && wl_resource_get_client (foco->res) == c)
    {
      struct wl_array teclas;
      wl_array_init (&teclas);
      wl_keyboard_send_enter (k, wl_display_next_serial (display), foco->res, &teclas);
      wl_array_release (&teclas);
      enviar_modificadores (k);
    }
}

static void
seat_get_touch (struct wl_client *c, struct wl_resource *r, uint32_t id)
{
  struct wl_resource *t = wl_resource_create (c, &wl_touch_interface,
					      wl_resource_get_version (r), id);
  if (t == NULL)
    wl_client_post_no_memory (c);
  else
    wl_resource_set_implementation (t, &touch_impl, NULL, NULL);
}

static const struct wl_seat_interface seat_impl = {
  .get_pointer = seat_get_pointer,
  .get_keyboard = seat_get_keyboard,
  .get_touch = seat_get_touch,
  .release = destruir_recurso,
};

static void
seat_bind (struct wl_client *c, void *data, uint32_t version, uint32_t id)
{
  struct wl_resource *r = wl_resource_create (c, &wl_seat_interface, version, id);
  wl_resource_set_implementation (r, &seat_impl, NULL, NULL);
  wl_seat_send_capabilities (r, WL_SEAT_CAPABILITY_POINTER | WL_SEAT_CAPABILITY_KEYBOARD);
  if (version >= WL_SEAT_NAME_SINCE_VERSION)
    wl_seat_send_name (r, "android");
}

/* ---------- zwp_pointer_gestures_v1 ---------- */

/* Solo deslizar (sway: bindgesture swipe:3:left ...); pellizcar y mantener se
   crean para que el cliente no falle, pero no mandan eventos.  */
static const struct zwp_pointer_gesture_swipe_v1_interface swipe_impl = {
  .destroy = destruir_recurso,
};

static const struct zwp_pointer_gesture_pinch_v1_interface pinch_impl = {
  .destroy = destruir_recurso,
};

static const struct zwp_pointer_gesture_hold_v1_interface hold_impl = {
  .destroy = destruir_recurso,
};

static void
gestos_get_swipe (struct wl_client *c, struct wl_resource *r, uint32_t id,
		  struct wl_resource *pointer)
{
  struct wl_resource *g = wl_resource_create (c, &zwp_pointer_gesture_swipe_v1_interface,
					      wl_resource_get_version (r), id);
  if (g == NULL)
    {
      wl_client_post_no_memory (c);
      return;
    }
  wl_resource_set_implementation (g, &swipe_impl, NULL, quitar_de_lista);
  wl_list_insert (&deslizar, wl_resource_get_link (g));
}

static void
gestos_get_pinch (struct wl_client *c, struct wl_resource *r, uint32_t id,
		  struct wl_resource *pointer)
{
  struct wl_resource *g = wl_resource_create (c, &zwp_pointer_gesture_pinch_v1_interface,
					      wl_resource_get_version (r), id);
  if (g == NULL)
    wl_client_post_no_memory (c);
  else
    wl_resource_set_implementation (g, &pinch_impl, NULL, NULL);
}

static void
gestos_get_hold (struct wl_client *c, struct wl_resource *r, uint32_t id,
		 struct wl_resource *pointer)
{
  struct wl_resource *g = wl_resource_create (c, &zwp_pointer_gesture_hold_v1_interface,
					      wl_resource_get_version (r), id);
  if (g == NULL)
    wl_client_post_no_memory (c);
  else
    wl_resource_set_implementation (g, &hold_impl, NULL, NULL);
}

static const struct zwp_pointer_gestures_v1_interface gestos_impl = {
  .get_swipe_gesture = gestos_get_swipe,
  .get_pinch_gesture = gestos_get_pinch,
  .release = destruir_recurso,
  .get_hold_gesture = gestos_get_hold,
};

static void
gestos_bind (struct wl_client *c, void *data, uint32_t version, uint32_t id)
{
  struct wl_resource *r = wl_resource_create (c, &zwp_pointer_gestures_v1_interface, version, id);
  wl_resource_set_implementation (r, &gestos_impl, NULL, NULL);
}

/* ---------- wl_output ---------- */

static const struct wl_output_interface output_impl = {
  .release = destruir_recurso,
};

static void
enviar_output (struct wl_resource *r)
{
  pthread_mutex_lock (&mtx);
  int w = vent_w, h = vent_h, mw = mm_w, mh = mm_h;
  pthread_mutex_unlock (&mtx);
  wl_output_send_geometry (r, 0, 0, mw, mh, WL_OUTPUT_SUBPIXEL_UNKNOWN,
			   "Android", "pantalla", WL_OUTPUT_TRANSFORM_NORMAL);
  wl_output_send_mode (r, WL_OUTPUT_MODE_CURRENT | WL_OUTPUT_MODE_PREFERRED,
		       w > 0 ? w : 1080, h > 0 ? h : 1920, 60000);
  if (wl_resource_get_version (r) >= WL_OUTPUT_SCALE_SINCE_VERSION)
    wl_output_send_scale (r, 1);
  if (wl_resource_get_version (r) >= WL_OUTPUT_NAME_SINCE_VERSION)
    {
      wl_output_send_name (r, "ANDROID-1");
      wl_output_send_description (r, "Pantalla del teléfono");
    }
  if (wl_resource_get_version (r) >= WL_OUTPUT_DONE_SINCE_VERSION)
    wl_output_send_done (r);
}

static void
output_bind (struct wl_client *c, void *data, uint32_t version, uint32_t id)
{
  struct wl_resource *r = wl_resource_create (c, &wl_output_interface, version, id);
  wl_resource_set_implementation (r, &output_impl, NULL, quitar_de_lista);
  wl_list_insert (&salidas, wl_resource_get_link (r));
  enviar_output (r);
}

/* ---------- entrada ---------- */

/* Coordenadas de la vista -> del buffer del foco.  */
static void
a_superficie (struct superficie *s, float x, float y, wl_fixed_t *fx, wl_fixed_t *fy)
{
  pthread_mutex_lock (&mtx);
  float ex = vent_w > 0 ? (float) s->buf_w / vent_w : 1;
  float ey = vent_h > 0 ? (float) s->buf_h / vent_h : 1;
  pthread_mutex_unlock (&mtx);
  *fx = wl_fixed_from_double (x * ex);
  *fy = wl_fixed_from_double (y * ey);
}

/* Punteros del cliente con foco (NULL si no hay a quién mandar).  */
static struct superficie *
foco_para_puntero (bool *entrar)
{
  struct superficie *s = foco;
  if (s == NULL || s->buf_w == 0)
    return NULL;
  *entrar = foco_puntero != s;
  foco_puntero = s;
  return s;
}

#define PARA_CADA_PUNTERO(p, s)						\
  wl_resource_for_each (p, &punteros)					\
    if (wl_resource_get_client (p) == wl_resource_get_client ((s)->res))

static wl_fixed_t ultimo_x, ultimo_y;

static void
fin_de_evento (struct wl_resource *p)
{
  if (wl_resource_get_version (p) >= WL_POINTER_FRAME_SINCE_VERSION)
    wl_pointer_send_frame (p);
}

static void
puntero_mover (float x, float y)
{
  bool entrar;
  struct superficie *s = foco_para_puntero (&entrar);
  if (s == NULL)
    return;
  a_superficie (s, x, y, &ultimo_x, &ultimo_y);
  struct wl_resource *p;
  PARA_CADA_PUNTERO (p, s)
    {
      if (entrar)
	wl_pointer_send_enter (p, wl_display_next_serial (display), s->res,
			       ultimo_x, ultimo_y);
      wl_pointer_send_motion (p, ahora_ms (), ultimo_x, ultimo_y);
      fin_de_evento (p);
    }
}

static void
puntero_boton (uint32_t boton, bool pulsado)
{
  bool entrar;
  struct superficie *s = foco_para_puntero (&entrar);
  if (s == NULL)
    return;
  struct wl_resource *p;
  PARA_CADA_PUNTERO (p, s)
    {
      if (entrar)
	wl_pointer_send_enter (p, wl_display_next_serial (display), s->res,
			       ultimo_x, ultimo_y);
      wl_pointer_send_button (p, wl_display_next_serial (display), ahora_ms (),
			      boton, pulsado ? WL_POINTER_BUTTON_STATE_PRESSED
					     : WL_POINTER_BUTTON_STATE_RELEASED);
      fin_de_evento (p);
    }
}

/* Scroll con dos dedos; dx = dy = 0 termina el gesto (axis_stop).  */
static void
puntero_eje (float dx, float dy)
{
  bool entrar;
  struct superficie *s = foco_para_puntero (&entrar);
  if (s == NULL)
    return;
  uint32_t t = ahora_ms ();
  struct wl_resource *p;
  PARA_CADA_PUNTERO (p, s)
    {
      if (entrar)
	wl_pointer_send_enter (p, wl_display_next_serial (display), s->res,
			       ultimo_x, ultimo_y);
      bool v5 = wl_resource_get_version (p) >= WL_POINTER_AXIS_SOURCE_SINCE_VERSION;
      if (v5)
	wl_pointer_send_axis_source (p, WL_POINTER_AXIS_SOURCE_FINGER);
      if (dx == 0 && dy == 0)
	{
	  if (v5)
	    {
	      wl_pointer_send_axis_stop (p, t, WL_POINTER_AXIS_VERTICAL_SCROLL);
	      wl_pointer_send_axis_stop (p, t, WL_POINTER_AXIS_HORIZONTAL_SCROLL);
	    }
	}
      else
	{
	  if (dy != 0)
	    wl_pointer_send_axis (p, t, WL_POINTER_AXIS_VERTICAL_SCROLL,
				  wl_fixed_from_double (dy));
	  if (dx != 0)
	    wl_pointer_send_axis (p, t, WL_POINTER_AXIS_HORIZONTAL_SCROLL,
				  wl_fixed_from_double (dx));
	}
      fin_de_evento (p);
    }
}

/* Deslizar con varios dedos: fase 0 empieza, 1 avanza (dx, dy en px de la
   vista), 2 termina, 3 se cancela.  */
static void
puntero_gesto (int fase, int dedos, float dx, float dy)
{
  bool entrar;
  struct superficie *s = foco_para_puntero (&entrar);
  if (s == NULL)
    return;
  struct wl_resource *p;
  if (entrar)
    PARA_CADA_PUNTERO (p, s)
      {
	wl_pointer_send_enter (p, wl_display_next_serial (display), s->res,
			       ultimo_x, ultimo_y);
	fin_de_evento (p);
      }
  wl_fixed_t fx, fy;
  a_superficie (s, dx, dy, &fx, &fy);
  uint32_t t = ahora_ms ();
  struct wl_resource *g;
  wl_resource_for_each (g, &deslizar)
    {
      if (wl_resource_get_client (g) != wl_resource_get_client (s->res))
	continue;
      if (fase == 0)
	zwp_pointer_gesture_swipe_v1_send_begin (g, wl_display_next_serial (display), t,
						 s->res, dedos);
      else if (fase == 1)
	zwp_pointer_gesture_swipe_v1_send_update (g, t, fx, fy);
      else
	zwp_pointer_gesture_swipe_v1_send_end (g, wl_display_next_serial (display), t,
					       fase == 3);
    }
}

static uint32_t
mascara_mod (uint32_t code)
{
  switch (code)
    {
    case KEY_LEFTSHIFT: case KEY_RIGHTSHIFT: return 1;	/* Shift */
    case KEY_LEFTCTRL: case KEY_RIGHTCTRL: return 4;	/* Control */
    case KEY_LEFTALT: return 8;			/* Mod1 */
    case KEY_RIGHTALT: return 128;		/* Mod5: AltGr (ISO_Level3) en latam */
    case KEY_LEFTMETA: case KEY_RIGHTMETA: return 64;	/* Mod4 */
    }
  return 0;
}

static void
tecla (uint32_t code, bool pulsada)
{
  uint32_t m = mascara_mod (code);
  uint32_t antes = mods;
  if (m != 0)
    mods = pulsada ? mods | m : mods & ~m;
  if (foco == NULL)
    return;
  struct wl_client *c = wl_resource_get_client (foco->res);
  struct wl_resource *k;
  wl_resource_for_each (k, &teclados)
    {
      if (wl_resource_get_client (k) != c)
	continue;
      wl_keyboard_send_key (k, wl_display_next_serial (display), ahora_ms (), code,
			    pulsada ? WL_KEYBOARD_KEY_STATE_PRESSED
				    : WL_KEYBOARD_KEY_STATE_RELEASED);
      if (mods != antes)
	enviar_modificadores (k);
    }
}

static int
procesar_cola (int fd, uint32_t mask, void *data)
{
  uint64_t n;
  read (evfd, &n, sizeof n);
  struct evento ev[512];
  pthread_mutex_lock (&mtx);
  int cuantos = ncola;
  memcpy (ev, cola, cuantos * sizeof *ev);
  ncola = 0;
  pthread_mutex_unlock (&mtx);
  for (int i = 0; i < cuantos; i++)
    switch (ev[i].tipo)
      {
      case EV_VENTANA:
	{
	  struct superficie *s;
	  wl_list_for_each (s, &toplevels, link)
	    if (s->configurado)
	      enviar_configure (s);
	  struct wl_resource *r;
	  wl_resource_for_each (r, &salidas)
	    enviar_output (r);
	  if (!wl_list_empty (&sin_ventana))
	    {
	      wl_list_insert_list (para_vsync.prev, &sin_ventana);
	      wl_list_init (&sin_ventana);
	      pedir_vsync ();
	    }
	  break;
	}
      case EV_MOVER:
	puntero_mover (ev[i].x, ev[i].y);
	break;
      case EV_BOTON:
	puntero_boton (ev[i].a & 0xffff, ev[i].a >> 16);
	break;
      case EV_EJE:
	puntero_eje (ev[i].x, ev[i].y);
	break;
      case EV_GESTO:
	puntero_gesto (ev[i].a & 0xff, ev[i].a >> 8, ev[i].x, ev[i].y);
	break;
      case EV_TECLA:
	tecla (ev[i].a & 0xffff, ev[i].a >> 16);
	break;
      case EV_TOMADA:
	tomada (ev[i].p);
	break;
      case EV_COMPLETADA:
	completada (ev[i].p);
	break;
      case EV_VSYNC:
	responder_callbacks (&para_vsync);
	break;
      }
  return 0;
}

static void
encolar (struct evento e)
{
  pthread_mutex_lock (&mtx);
  if (ncola < (int) (sizeof cola / sizeof cola[0]))
    cola[ncola++] = e;
  pthread_mutex_unlock (&mtx);
  uint64_t uno = 1;
  if (evfd >= 0)
    write (evfd, &uno, sizeof uno);
}

static void
encolar_transaccion (int tipo, struct transaccion *t)
{
  encolar ((struct evento) { .tipo = tipo, .p = t });
}

/* ---------- vsync ----------
   AChoreographer solo se usa desde un hilo con ALooper: el hilo del anfitrión
   le pide un vsync escribiendo en un eventfd que ese looper vigila.  */

static int vsync_fd = -1;

static void
vsync (int64_t ns, void *data)
{
  encolar ((struct evento) { .tipo = EV_VSYNC });
}

static int
vsync_pedido (int fd, int events, void *data)
{
  uint64_t n;
  read (fd, &n, sizeof n);
  AChoreographer_postFrameCallback64 (AChoreographer_getInstance (), vsync, NULL);
  return 1;
}

static void *
hilo_vsync (void *arg)
{
  ALooper *looper = ALooper_prepare (0);
  ALooper_addFd (looper, vsync_fd, 0, ALOOPER_EVENT_INPUT, vsync_pedido, NULL);
  AChoreographer_getInstance ();
  for (;;)
    ALooper_pollOnce (-1, NULL, NULL, NULL);
  return NULL;
}

static void
pedir_vsync (void)
{
  uint64_t uno = 1;
  write (vsync_fd, &uno, sizeof uno);
}

/* ---------- arranque y JNI ---------- */

static void *
hilo (void *arg)
{
  LOG ("anfitrión Wayland corriendo");
  wl_display_run (display);
  return NULL;
}

JNIEXPORT jboolean JNICALL
Java_dev_ben4shot_glibcprueba_Wayland_iniciar (JNIEnv *env, jclass cls, jstring jdir)
{
  if (display != NULL)
    return JNI_TRUE;
  const char *dir = (*env)->GetStringUTFChars (env, jdir, NULL);
  setenv ("XDG_RUNTIME_DIR", dir, 1);
  (*env)->ReleaseStringUTFChars (env, jdir, dir);

  wl_list_init (&toplevels);
  wl_list_init (&punteros);
  wl_list_init (&teclados);
  wl_list_init (&salidas);
  wl_list_init (&deslizar);
  display = wl_display_create ();
  if (wl_display_add_socket (display, "wayland-0") != 0)
    {
      LOG ("no se pudo crear el socket wayland-0");
      wl_display_destroy (display);
      display = NULL;
      return JNI_FALSE;
    }
  wl_display_init_shm (display);
  wl_display_add_shm_format (display, WL_SHM_FORMAT_XBGR8888);
  wl_display_add_shm_format (display, WL_SHM_FORMAT_ABGR8888);
  wl_global_create (display, &wl_compositor_interface, 6, NULL, compositor_bind);
  wl_global_create (display, &xdg_wm_base_interface, 2, NULL, wm_base_bind);
  wl_global_create (display, &wl_seat_interface, 7, NULL, seat_bind);
  wl_global_create (display, &wl_output_interface, 4, NULL, output_bind);
  wl_global_create (display, &zwp_pointer_gestures_v1_interface, 3, NULL, gestos_bind);
  wl_global_create (display, &zwp_linux_dmabuf_v1_interface, 3, NULL, linux_dmabuf_bind);
  wl_global_create (display, &android_ahb_v1_interface, 1, NULL, android_ahb_bind);

  wl_list_init (&para_vsync);
  wl_list_init (&sin_ventana);
  vsync_fd = eventfd (0, EFD_CLOEXEC | EFD_NONBLOCK);
  pthread_t tv;
  pthread_create (&tv, NULL, hilo_vsync, NULL);
  pthread_detach (tv);
  evfd = eventfd (0, EFD_CLOEXEC | EFD_NONBLOCK);
  wl_event_loop_add_fd (wl_display_get_event_loop (display), evfd,
			WL_EVENT_READABLE, procesar_cola, NULL);
  pthread_t t;
  pthread_create (&t, NULL, hilo, NULL);
  pthread_detach (t);
  return JNI_TRUE;
}

JNIEXPORT void JNICALL
Java_dev_ben4shot_glibcprueba_Wayland_ventana (JNIEnv *env, jclass cls, jobject surface,
					       jint w, jint h, jint mmw, jint mmh)
{
  pthread_mutex_lock (&mtx);
  if (capa != NULL)
    {
      ASurfaceTransaction *tr = ASurfaceTransaction_create ();
      ASurfaceTransaction_reparent (tr, capa, NULL);
      ASurfaceTransaction_apply (tr);
      ASurfaceTransaction_delete (tr);
      ASurfaceControl_release (capa);
      capa = NULL;
    }
  if (ventana != NULL)
    ANativeWindow_release (ventana);
  ventana = surface != NULL ? ANativeWindow_fromSurface (env, surface) : NULL;
  if (ventana != NULL)
    {
      vent_w = w;
      vent_h = h;
      mm_w = mmw;
      mm_h = mmh;
      mostrar ();
      capa = ASurfaceControl_createFromWindow (ventana, "linux");
      if (capa != NULL && en_pantalla != NULL)
	{
	  /* Volver a mostrar el último cuadro (SurfaceFlinger aún lo retiene).  */
	  ASurfaceTransaction *tr = ASurfaceTransaction_create ();
	  ASurfaceTransaction_setBuffer (tr, capa, en_pantalla->ahb, -1);
	  geometria (tr, capa, en_pantalla, w, h);
	  ASurfaceTransaction_setBufferTransparency (tr, capa, ASURFACE_TRANSACTION_TRANSPARENCY_OPAQUE);
	  ASurfaceTransaction_apply (tr);
	  ASurfaceTransaction_delete (tr);
	}
    }
  pthread_mutex_unlock (&mtx);
  if (ventana != NULL)
    encolar ((struct evento) { .tipo = EV_VENTANA });
}

JNIEXPORT void JNICALL
Java_dev_ben4shot_glibcprueba_Wayland_mover (JNIEnv *env, jclass cls, jfloat x, jfloat y)
{
  encolar ((struct evento) { .tipo = EV_MOVER, .x = x, .y = y });
}

JNIEXPORT void JNICALL
Java_dev_ben4shot_glibcprueba_Wayland_boton (JNIEnv *env, jclass cls, jint boton,
					     jboolean pulsado)
{
  encolar ((struct evento) { .tipo = EV_BOTON, .a = (boton & 0xffff) | (pulsado ? 1 << 16 : 0) });
}

JNIEXPORT void JNICALL
Java_dev_ben4shot_glibcprueba_Wayland_eje (JNIEnv *env, jclass cls, jfloat dx, jfloat dy)
{
  encolar ((struct evento) { .tipo = EV_EJE, .x = dx, .y = dy });
}

JNIEXPORT void JNICALL
Java_dev_ben4shot_glibcprueba_Wayland_tecla (JNIEnv *env, jclass cls, jint code,
					     jboolean pulsada)
{
  encolar ((struct evento) { .tipo = EV_TECLA, .a = (code & 0xffff) | (pulsada ? 1 << 16 : 0) });
}

JNIEXPORT void JNICALL
Java_dev_ben4shot_glibcprueba_Wayland_gesto (JNIEnv *env, jclass cls, jint fase, jint dedos,
					     jfloat dx, jfloat dy)
{
  encolar ((struct evento) { .tipo = EV_GESTO, .a = (fase & 0xff) | (dedos << 8), .x = dx, .y = dy });
}
