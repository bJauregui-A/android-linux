/* Prueba de cero copias (android-ahb-v1): pide buffers al anfitrión
   (AHardwareBuffer), los importa en Turnip como dmabuf, los limpia con un color
   que cambia en cada cuadro y los adjunta.  Sincronización como la WSI de Mesa:
   la fence del render (semáforo sync_fd) se le pega al dmabuf antes del commit,
   y antes de volver a usar un buffer se espera lo que el anfitrión le pegó.
   Al final: cuadros por segundo y CPU usada.

   Compilar (dentro del Arch de la app, con los .c/.h del protocolo al lado):
     gcc -O2 -o prueba-ahb prueba-ahb.c xdg-shell-protocol.c android-ahb-v1-protocol.c \
         -lwayland-client -lvulkan
   Uso: prueba-ahb [segundos] [bgra]  (WAYLAND_DISPLAY directo al anfitrión;
   bgra: ARGB8888 / VK_FORMAT_B8G8R8A8_UNORM en vez de ABGR8888 / R8G8B8A8)  */

#include <errno.h>
#include <linux/dma-buf.h>
#include <math.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/resource.h>
#include <time.h>
#include <unistd.h>
#include <vulkan/vulkan.h>
#include <wayland-client.h>

#include "android-ahb-v1-client-protocol.h"
#include "xdg-shell-client-protocol.h"

#define DRM_ABGR8888 0x34324241
#define DRM_ARGB8888 0x34325241
#define NBUF 3
#define FALLA(...) do { fprintf (stderr, __VA_ARGS__); fputc ('\n', stderr); exit (1); } while (0)
#define VK(x) do { VkResult r_ = (x); if (r_ != VK_SUCCESS) FALLA ("%s: %d", #x, r_); } while (0)

static struct wl_compositor *compositor;
static struct xdg_wm_base *wm_base;
static struct android_ahb_v1 *ahb_global;
static int ancho, alto, configurado, cerrar;

struct buf
{
  struct wl_buffer *wl;
  int fd, ocupado, listo;
  unsigned offset, stride;
  VkImage img;
  VkDeviceMemory mem;
  VkCommandBuffer cmd;
  VkSemaphore sem;
  VkFence fence;
} bufs[NBUF];

static void
reg_global (void *d, struct wl_registry *r, uint32_t name, const char *iface, uint32_t v)
{
  if (strcmp (iface, wl_compositor_interface.name) == 0)
    compositor = wl_registry_bind (r, name, &wl_compositor_interface, 4);
  else if (strcmp (iface, xdg_wm_base_interface.name) == 0)
    wm_base = wl_registry_bind (r, name, &xdg_wm_base_interface, 1);
  else if (strcmp (iface, android_ahb_v1_interface.name) == 0)
    ahb_global = wl_registry_bind (r, name, &android_ahb_v1_interface, 1);
}
static void reg_quitar (void *d, struct wl_registry *r, uint32_t name) { }
static const struct wl_registry_listener reg_l = { reg_global, reg_quitar };

static void wm_ping (void *d, struct xdg_wm_base *b, uint32_t s) { xdg_wm_base_pong (b, s); }
static const struct xdg_wm_base_listener wm_l = { wm_ping };

static void xs_configure (void *d, struct xdg_surface *s, uint32_t serial)
{
  xdg_surface_ack_configure (s, serial);
  configurado = 1;
}
static const struct xdg_surface_listener xs_l = { xs_configure };

static void
tl_configure (void *d, struct xdg_toplevel *t, int32_t w, int32_t h, struct wl_array *st)
{
  if (w > 0 && h > 0)
    {
      ancho = w;
      alto = h;
    }
}
static void tl_close (void *d, struct xdg_toplevel *t) { cerrar = 1; }
static const struct xdg_toplevel_listener tl_l = { tl_configure, tl_close };

static void
ahb_listo (void *d, struct android_ahb_v1 *a, struct wl_buffer *wb, int32_t fd,
	   uint32_t offset, uint32_t stride)
{
  for (int i = 0; i < NBUF; i++)
    if (bufs[i].wl == wb)
      {
	bufs[i].fd = fd;
	bufs[i].offset = offset;
	bufs[i].stride = stride;
	bufs[i].listo = 1;
      }
}
static void ahb_fallo (void *d, struct android_ahb_v1 *a, struct wl_buffer *wb)
{
  FALLA ("el anfitrión no pudo reservar el buffer");
}
static const struct android_ahb_v1_listener ahb_l = { ahb_listo, ahb_fallo };

static void
buf_release (void *d, struct wl_buffer *wb)
{
  ((struct buf *) d)->ocupado = 0;
}
static const struct wl_buffer_listener buf_l = { buf_release };

static int frame_pendiente;
static void frame_done (void *d, struct wl_callback *cb, uint32_t t)
{
  frame_pendiente = 0;
  wl_callback_destroy (cb);
}
static const struct wl_callback_listener frame_l = { frame_done };

static double
ahora (void)
{
  struct timespec t;
  clock_gettime (CLOCK_MONOTONIC, &t);
  return t.tv_sec + t.tv_nsec / 1e9;
}

static double
cpu (void)
{
  struct rusage u;
  getrusage (RUSAGE_SELF, &u);
  return u.ru_utime.tv_sec + u.ru_utime.tv_usec / 1e6 + u.ru_stime.tv_sec
	 + u.ru_stime.tv_usec / 1e6;
}

int
main (int argc, char **argv)
{
  double segundos = argc > 1 ? atof (argv[1]) : 10;
  int bgra = argc > 2 && strcmp (argv[2], "bgra") == 0;
  struct wl_display *dpy = wl_display_connect (NULL);
  if (dpy == NULL)
    FALLA ("no hay conexión Wayland");
  struct wl_registry *reg = wl_display_get_registry (dpy);
  wl_registry_add_listener (reg, &reg_l, NULL);
  wl_display_roundtrip (dpy);
  if (compositor == NULL || wm_base == NULL || ahb_global == NULL)
    FALLA ("falta wl_compositor, xdg_wm_base o android_ahb_v1");
  xdg_wm_base_add_listener (wm_base, &wm_l, NULL);
  android_ahb_v1_add_listener (ahb_global, &ahb_l, NULL);

  struct wl_surface *surf = wl_compositor_create_surface (compositor);
  struct xdg_surface *xs = xdg_wm_base_get_xdg_surface (wm_base, surf);
  xdg_surface_add_listener (xs, &xs_l, NULL);
  struct xdg_toplevel *tl = xdg_surface_get_toplevel (xs);
  xdg_toplevel_add_listener (tl, &tl_l, NULL);
  xdg_toplevel_set_title (tl, "prueba-ahb");
  wl_surface_commit (surf);
  while (!configurado)
    wl_display_dispatch (dpy);
  if (ancho == 0)
    ancho = 1080, alto = 1134;
  printf ("ventana %dx%d\n", ancho, alto);

  for (int i = 0; i < NBUF; i++)
    {
      bufs[i].wl = android_ahb_v1_crear (ahb_global, ancho, alto,
					   bgra ? DRM_ARGB8888 : DRM_ABGR8888);
      wl_buffer_add_listener (bufs[i].wl, &buf_l, &bufs[i]);
    }
  wl_display_roundtrip (dpy);
  for (int i = 0; i < NBUF; i++)
    {
      if (!bufs[i].listo)
	FALLA ("buffer %d sin respuesta", i);
      printf ("buffer %d: fd %d offset %u stride %u\n", i, bufs[i].fd, bufs[i].offset,
	      bufs[i].stride);
    }

  /* Vulkan */
  VkInstance inst;
  VK (vkCreateInstance (&(VkInstanceCreateInfo) {
	.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
	.pApplicationInfo = &(VkApplicationInfo) {
	  .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO, .apiVersion = VK_API_VERSION_1_3 } },
      NULL, &inst));
  uint32_t n = 1;
  VkPhysicalDevice pd;
  vkEnumeratePhysicalDevices (inst, &n, &pd);
  if (n == 0)
    FALLA ("sin GPU Vulkan");
  VkPhysicalDeviceProperties props;
  vkGetPhysicalDeviceProperties (pd, &props);
  printf ("GPU: %s\n", props.deviceName);
  const char *exts[] = {
    VK_KHR_EXTERNAL_MEMORY_FD_EXTENSION_NAME, VK_EXT_EXTERNAL_MEMORY_DMA_BUF_EXTENSION_NAME,
    VK_EXT_IMAGE_DRM_FORMAT_MODIFIER_EXTENSION_NAME, VK_KHR_EXTERNAL_SEMAPHORE_FD_EXTENSION_NAME,
    VK_EXT_QUEUE_FAMILY_FOREIGN_EXTENSION_NAME,
  };
  VkDevice dev;
  VK (vkCreateDevice (pd, &(VkDeviceCreateInfo) {
	.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
	.queueCreateInfoCount = 1,
	.pQueueCreateInfos = &(VkDeviceQueueCreateInfo) {
	  .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, .queueCount = 1,
	  .pQueuePriorities = &(float) { 1 } },
	.enabledExtensionCount = sizeof exts / sizeof *exts, .ppEnabledExtensionNames = exts },
      NULL, &dev));
  VkQueue cola;
  vkGetDeviceQueue (dev, 0, 0, &cola);
  PFN_vkGetMemoryFdPropertiesKHR getFdProps =
    (void *) vkGetDeviceProcAddr (dev, "vkGetMemoryFdPropertiesKHR");
  PFN_vkGetSemaphoreFdKHR getSemFd = (void *) vkGetDeviceProcAddr (dev, "vkGetSemaphoreFdKHR");
  VkCommandPool pool;
  VK (vkCreateCommandPool (dev, &(VkCommandPoolCreateInfo) {
	.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
	.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT }, NULL, &pool));

  for (int i = 0; i < NBUF; i++)
    {
      struct buf *b = &bufs[i];
      VkSubresourceLayout plano = { .offset = b->offset, .rowPitch = b->stride };
      VK (vkCreateImage (dev, &(VkImageCreateInfo) {
	    .sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
	    .pNext = &(VkExternalMemoryImageCreateInfo) {
	      .sType = VK_STRUCTURE_TYPE_EXTERNAL_MEMORY_IMAGE_CREATE_INFO,
	      .pNext = &(VkImageDrmFormatModifierExplicitCreateInfoEXT) {
		.sType = VK_STRUCTURE_TYPE_IMAGE_DRM_FORMAT_MODIFIER_EXPLICIT_CREATE_INFO_EXT,
		.drmFormatModifier = 0, .drmFormatModifierPlaneCount = 1,
		.pPlaneLayouts = &plano },
	      .handleTypes = VK_EXTERNAL_MEMORY_HANDLE_TYPE_DMA_BUF_BIT_EXT },
	    .imageType = VK_IMAGE_TYPE_2D, .format = bgra ? VK_FORMAT_B8G8R8A8_UNORM : VK_FORMAT_R8G8B8A8_UNORM,
	    .extent = { ancho, alto, 1 }, .mipLevels = 1, .arrayLayers = 1,
	    .samples = VK_SAMPLE_COUNT_1_BIT,
	    .tiling = VK_IMAGE_TILING_DRM_FORMAT_MODIFIER_EXT,
	    .usage = VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT },
	  NULL, &b->img));
      VkMemoryFdPropertiesKHR fdp = { .sType = VK_STRUCTURE_TYPE_MEMORY_FD_PROPERTIES_KHR };
      VK (getFdProps (dev, VK_EXTERNAL_MEMORY_HANDLE_TYPE_DMA_BUF_BIT_EXT, b->fd, &fdp));
      VkMemoryRequirements req;
      vkGetImageMemoryRequirements (dev, b->img, &req);
      uint32_t tipos = req.memoryTypeBits & fdp.memoryTypeBits;
      if (tipos == 0)
	FALLA ("ningún tipo de memoria admite el dmabuf");
      int dup_fd = dup (b->fd);	/* Vulkan se queda con el fd importado */
      VK (vkAllocateMemory (dev, &(VkMemoryAllocateInfo) {
	    .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
	    .pNext = &(VkImportMemoryFdInfoKHR) {
	      .sType = VK_STRUCTURE_TYPE_IMPORT_MEMORY_FD_INFO_KHR,
	      .pNext = &(VkMemoryDedicatedAllocateInfo) {
		.sType = VK_STRUCTURE_TYPE_MEMORY_DEDICATED_ALLOCATE_INFO, .image = b->img },
	      .handleType = VK_EXTERNAL_MEMORY_HANDLE_TYPE_DMA_BUF_BIT_EXT, .fd = dup_fd },
	    .allocationSize = req.size, .memoryTypeIndex = __builtin_ctz (tipos) },
	  NULL, &b->mem));
      VK (vkBindImageMemory (dev, b->img, b->mem, 0));
      VK (vkAllocateCommandBuffers (dev, &(VkCommandBufferAllocateInfo) {
	    .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO, .commandPool = pool,
	    .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY, .commandBufferCount = 1 }, &b->cmd));
      VK (vkCreateSemaphore (dev, &(VkSemaphoreCreateInfo) {
	    .sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
	    .pNext = &(VkExportSemaphoreCreateInfo) {
	      .sType = VK_STRUCTURE_TYPE_EXPORT_SEMAPHORE_CREATE_INFO,
	      .handleTypes = VK_EXTERNAL_SEMAPHORE_HANDLE_TYPE_SYNC_FD_BIT } },
	  NULL, &b->sem));
      VK (vkCreateFence (dev, &(VkFenceCreateInfo) {
	    .sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO, .flags = VK_FENCE_CREATE_SIGNALED_BIT },
	  NULL, &b->fence));
    }
  printf ("dmabuf importados en Vulkan\n");

  double t0 = ahora (), c0 = cpu ();
  int cuadros = 0, esperas = 0;
  while (!cerrar && ahora () - t0 < segundos)
    {
      while (frame_pendiente)
	if (wl_display_dispatch (dpy) < 0)
	  FALLA ("conexión cerrada");
      struct buf *b = NULL;
      while (b == NULL)
	{
	  for (int i = 0; i < NBUF && b == NULL; i++)
	    if (!bufs[i].ocupado)
	      b = &bufs[i];
	  if (b == NULL)
	    {
	      esperas++;
	      wl_display_dispatch (dpy);
	    }
	}
      /* Lo que el anfitrión le pegó al dmabuf (release de SurfaceFlinger):
	 aquí se espera con la CPU; la WSI lo convierte en semáforo.  */
      struct pollfd pfd = { b->fd, POLLOUT, 0 };
      poll (&pfd, 1, 100);
      vkWaitForFences (dev, 1, &b->fence, VK_TRUE, UINT64_MAX);
      vkResetFences (dev, 1, &b->fence);

      float h = cuadros / 120.0f * 6.2832f;
      VkClearColorValue color = { .float32 = { 0.5f + 0.5f * sinf (h), 0.5f + 0.5f * sinf (h + 2.1f),
					       0.5f + 0.5f * sinf (h + 4.2f), 1 } };
      VkImageSubresourceRange rango = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1 };
      vkBeginCommandBuffer (b->cmd, &(VkCommandBufferBeginInfo) {
	.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO });
      vkCmdPipelineBarrier (b->cmd, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
			    VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, NULL, 0, NULL, 1,
			    &(VkImageMemoryBarrier) {
			      .sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
			      .dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT,
			      .oldLayout = VK_IMAGE_LAYOUT_UNDEFINED,
			      .newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
			      .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
			      .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
			      .image = b->img, .subresourceRange = rango });
      vkCmdClearColorImage (b->cmd, b->img, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, &color, 1,
			    &rango);
      vkCmdPipelineBarrier (b->cmd, VK_PIPELINE_STAGE_TRANSFER_BIT,
			    VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, 0, 0, NULL, 0, NULL, 1,
			    &(VkImageMemoryBarrier) {
			      .sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
			      .srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT,
			      .oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
			      .newLayout = VK_IMAGE_LAYOUT_GENERAL,
			      .srcQueueFamilyIndex = 0,
			      .dstQueueFamilyIndex = VK_QUEUE_FAMILY_FOREIGN_EXT,
			      .image = b->img, .subresourceRange = rango });
      vkEndCommandBuffer (b->cmd);
      VK (vkQueueSubmit (cola, 1, &(VkSubmitInfo) {
	    .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO, .commandBufferCount = 1,
	    .pCommandBuffers = &b->cmd, .signalSemaphoreCount = 1,
	    .pSignalSemaphores = &b->sem }, b->fence));
      int sync_fd = -1;
      VK (getSemFd (dev, &(VkSemaphoreGetFdInfoKHR) {
	    .sType = VK_STRUCTURE_TYPE_SEMAPHORE_GET_FD_INFO_KHR, .semaphore = b->sem,
	    .handleType = VK_EXTERNAL_SEMAPHORE_HANDLE_TYPE_SYNC_FD_BIT }, &sync_fd));
      struct dma_buf_import_sync_file imp = { DMA_BUF_SYNC_RW, sync_fd };
      if (ioctl (b->fd, DMA_BUF_IOCTL_IMPORT_SYNC_FILE, &imp) != 0)
	FALLA ("IMPORT_SYNC_FILE: %s", strerror (errno));
      close (sync_fd);

      wl_surface_attach (surf, b->wl, 0, 0);
      wl_surface_damage (surf, 0, 0, ancho, alto);
      wl_callback_add_listener (wl_surface_frame (surf), &frame_l, NULL);
      frame_pendiente = 1;
      b->ocupado = 1;
      wl_surface_commit (surf);
      wl_display_flush (dpy);
      cuadros++;
    }
  double t = ahora () - t0, c = cpu () - c0;
  printf ("%d cuadros en %.1f s = %.1f fps; CPU del cliente %.2f s (%.0f %%); "
	  "esperas por buffer libre: %d\n",
	  cuadros, t, cuadros / t, c, 100 * c / t, esperas);
  vkDeviceWaitIdle (dev);
  return 0;
}
