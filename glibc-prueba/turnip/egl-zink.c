/* OpenGL por GPU (Zink sobre Turnip) en ventanas Wayland sin dmabuf.

   Sin nodo DRM, EGL en Wayland solo sirve por el camino "swrast" (wl_shm),
   y ahí usa Zink con kopper (presenta por la WSI de Vulkan, que con
   MESA_VK_WSI_DEBUG=sw también sale por wl_shm) solo si ve a la vez
   MESA_LOADER_DRIVER_OVERRIDE=zink y LIBGL_ALWAYS_SOFTWARE=1.  Pero Zink lee
   la misma LIBGL_ALWAYS_SOFTWARE y entonces exige una GPU de CPU (lavapipe).
   Sin la variable, EGL reintenta sin Zink y carga zink como driver "sw":
   cuadros negros.

   Esta biblioteca (LD_PRELOAD) le dice LIBGL_ALWAYS_SOFTWARE=1 solo a
   libEGL_mesa; Zink y el resto ven el entorno real.  Así sigue sirviendo
   cuando pacman actualiza el mesa de Arch.  Se compila dentro del Arch de la
   app (lo hace turnip/compilar-mesa.sh):
     gcc -O2 -shared -fPIC -o ~/turnip/lib/libegl-zink.so egl-zink.c  */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>

char *
getenv (const char *nombre)
{
  static char *(*real) (const char *);
  if (real == NULL)
    real = dlsym (RTLD_NEXT, "getenv");
  if (strcmp (nombre, "LIBGL_ALWAYS_SOFTWARE") == 0)
    {
      Dl_info info;
      if (dladdr (__builtin_return_address (0), &info) && info.dli_fname != NULL
	  && strstr (info.dli_fname, "libEGL_mesa") != NULL)
	return "1";
    }
  return real (nombre);
}
