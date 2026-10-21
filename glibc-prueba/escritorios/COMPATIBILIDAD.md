# Contrato de escritorios y proveedores de pantalla

Los perfiles de `escritorios/` describen configuración y arranque; los proveedores de
`escritorios/proveedores/` describen cómo conectarlos a una pantalla. La receta efectiva combina
distribución + escritorio: paquetes y ajustes del OS no se presuponen intercambiables. Que un
paquete exista o que su comando esté en `sesion` no significa que ya esté probado.
`escritorio.conf` conserva `ESTADO=sin-probar` hasta validar el entorno real.

## Contrato del perfil (`escritorio.conf`)

- `PROVEEDOR_PANTALLA`: ID del proveedor requerido.
- `REQUISITOS_SESION`: requisitos separados por espacios, por ejemplo `dbus-session wayland`.
- `CAPACIDADES_REQUERIDAS`: capacidades que debe ofrecer el proveedor.
- `READY_LEVEL`: etapa que declara el perfil. `proveedor-y-proceso` solo significa que el proveedor
  pasó su comprobación y que el proceso del perfil sigue vivo; no acredita presentación, entrada ni
  interactividad.
- `sesion`: inicia los procesos del perfil en primer plano; normalmente termina con `exec`.
- `paquetes.txt`, `home/` y `ESTADO`: dependencias para la distribución que instala el perfil,
  configuración inicial y nivel de validación.

## Contrato del proveedor (`proveedor.conf`)

- `PROTOCOLO_PANTALLA`, `TIPO_SESION` y las variables de conexión describen el entorno inyectado
  al perfil.
- `CAPACIDADES_PROVEEDOR` enumera capacidades ofrecidas; no se infieren del nombre del compositor.
- `COMPROBACION_READY` y `TIEMPO_READY` identifican la comprobación del supervisor. Una
  comprobación desconocida es un error explícito.
- El marcador publicado en `$XDG_RUNTIME_DIR` expone el endpoint listo a TerminalService y los
  servicios.

El proveedor activo `wayland-anidado` conecta el compositor al `WAYLAND_DISPLAY` anfitrión y espera
un socket Wayland nuevo. Todos los perfiles actuales lo solicitan explícitamente. Esto comprueba
disponibilidad del endpoint, no que el compositor haya presentado un cuadro. Otros proveedores
(por ejemplo, X11 anidado) necesitan su contrato y su comprobación de readiness antes de usarse.

## Ciclo común (mínimo)

- `primer-arranque.sh` (hoy solo Arch ARM64) instala sus paquetes y aplica el overlay `home/` de la
  receta al seleccionar/instalar el perfil, sin sobrescribir configuraciones existentes.
- `sesion-android` carga el perfil y proveedor, valida los requisitos declarados y ejecuta el
  lanzador específico del escritorio. Expone `ARCH_ANDROID_DESKTOP` y reserva
  `ARCH_ANDROID_WAYLAND_SOCKET` para recetas que deben declarar el socket del compositor.
- Al superar readiness, publica el endpoint y lanza los servicios comunes. Si falla, termina el
  intento y conserva la elección y su log; Sway solo se usa como rescate de una receta ausente o
  cuando `LINUX_SESSION_FALLBACK_ON_FAILURE=1` se solicita explícitamente.
- `sesion-android` también inicia `autostart-android` tras detectar el socket, incluidos los
  servicios comunes que antes iniciaba sway desde su configuración.
- Antes de iniciar el escritorio, Android sincroniza desde la APK solo los supervisores/perfiles
  Linux gestionados por el proyecto, con hash de versión; no reextrae ni pisa el rootfs entero.
- Al llegar a readiness, `sesion-android` publica `linux-session.properties` con protocolo,
  variable de conexión, endpoint y capacidades. `TerminalService` usa ese contrato para conectar
  clientes Linux y ya no fuerza Wayland cuando el proveedor declara X11. El marcador específico del
  proveedor sigue usándose para readiness.
- `sesion-android` crea un único bus D-Bus de sesión, publica su dirección y actualiza el entorno
  de activación cuando conoce el endpoint. Solo intenta iniciar un `systemd --user` real si el
  perfil lo exige; cuando está disponible importa el entorno gráfico e inicia/detiene
  `graphical-session.target`. Android no arrancó con systemd, así que no se debe asumir que ese
  gestor puede iniciarse como hijo ni simular `org.freedesktop.systemd1`. Los perfiles que lo
  requieran fallan de forma explícita al rescate; los entornos con modo clásico deben declarar
  sus propios requisitos.
- `autostart-android` supervisa los procesos de servicio que inicia. Al cerrar solicita primero
  el cierre ordenado de Steam por sway IPC cuando está disponible y luego detiene esos procesos.
- El puente del portapapeles Android usa `wl-paste`/`wl-copy` y se activa solo con Wayland; para X11
  se requiere un backend de portapapeles compatible antes de declarar esa capacidad.
- Las dependencias van en manifiestos específicos de distribución; las variables/pasos propios del
  DE pertenecen a su receta, y las de conexión/readiness al proveedor, no a `TerminalService`.

## Límites conocidos

El anfitrión Android actual ofrece una superficie Wayland anidada. No ofrece DRM/KMS, sesión
logind, udev completo ni systemd de sistema. No se puede iniciar un systemd de usuario convencional
sin ese system manager; los perfiles activos declaran
Wayland; modos DRM, TTY o sesiones que exijan logind/systemd no son compatibles sin adaptaciones.
La arquitectura acepta otros proveedores, pero eso no significa que estén implementados.

La ruta Vulkan/Android AHardwareBuffer está implementada en el wlroots parcheado. Solo los
compositores que realmente carguen esa biblioteca aprovechan ese camino; otros pueden necesitar
renderer software o su propio soporte de buffers. Xwayland tampoco es una capacidad universal:
debe comprobarse compositor por compositor. El arranque de Steam sigue dependiendo de `DISPLAY`,
por lo que los perfiles sin Xwayland no obtienen Steam automáticamente.

## Estado del anfitrión Wayland y shim DRM/GBM/DMA-BUF (51ª sesión)

- **Anfitrión Wayland nativo (`app/src/main/cpp/anfitrion.c`):** expone `wl_compositor` v6, `wl_subcompositor` v1 (resolviendo subsurfaces hijas a la superficie raíz en `surface_commit`), `wl_shm` v1, `wl_output` v4, `wl_seat` v9, `xdg_wm_base` v6, `zwp_linux_dmabuf_v1` v4 (con `get_default_feedback`/`get_surface_feedback` y tabla `memfd` sellada anunciando `makedev(10, 123)`), `wp_viewporter` v1, `wp_single_pixel_buffer_manager_v1` v1, `wp_presentation` v1, `zwp_pointer_constraints_v1` v1, `zwp_relative_pointer_manager_v1` v1 y `android_ahb_v1`.
- **Shim universal (`turnip/udmabuf-shim.c` → `/usr/local/lib/libudmabuf-shim.so`):** inyectado por `proveedores/wayland-anidado/proveedor.conf`. Emula `/dev/udmabuf`, `/dev/dri/renderD128` y `/dev/dri/card0` sobre DMA-BUFs reales del kernel Android (`/dev/dma_heap/system` con fallback `/dev/kgsl-3d0`), implementa las APIs de `libdrm` y `libgbm` requeridas por compositores Wayland y `Xwayland`, y expone `EGLDeviceEXT` con nodo DRM virtual para que `kwin_wayland`, `Hyprland`/`Aquamarine` y demás compositores aceleren por GPU con Zink+Turnip sin DRM del kernel.

## Notas por perfil

- **KDE Plasma (`kde`, `ESTADO=probado`):** inicia `kwin_wayland` anidado con `iniciar-plasma-android` (`kded6` + `plasmashell`), renderizando con OpenGL 4.6 sobre Zink+Turnip (`libudmabuf-shim.so`) y presentando su `wl_subsurface` en el anfitrión Android. Validado en el dispositivo.
- **Hyprland (`hyprland`, `ESTADO=probado`):** perfil completo en `escritorios/hyprland/` con `Hyprland` `0.56.2-4` + `aquamarine` `0.15.1-1` de Arch ARM sin recompilar, configuración adaptada a la pantalla del teléfono (`1080×2193@60`, escala `2.5`, distribución `latam`) y `waybar`. Validado corriendo en el dispositivo.
- **COSMIC (`cosmic`):** el perfil selecciona `COSMIC_BACKEND=winit` y `WINIT_UNIX_BACKEND=wayland`; paquetes instalados en el teléfono, pendiente prueba interactiva.
- **Niri (`niri`):** paquetes e `home/` instalados en el teléfono; pendiente prueba interactiva.
- **labwc, Wayfire, Phosh, River, Qtile, XFCE, LXQt y Weston:** todos los paquetes de Arch ARM y sus configuraciones iniciales `home/` ya están instalados en el contenedor del teléfono; falta recorrerlos uno por uno desde el selector para validar presentación y entrada.

## Validación pendiente

Probar en el dispositivo, perfil por perfil: arranque anidado y socket, presentación, tacto/teclado,
escala y giro, clientes Wayland, portapapeles, audio y Xwayland cuando aplique. Marcar `probado`
solo después de confirmar esos puntos. No se deben considerar probados KDE, COSMIC, Weston, niri,
Phosh ni los demás perfiles solo por tener receta de arranque. El barrido de la APK solo confirma
que apareció un socket y el proceso siguió vivo tres segundos; no reemplaza las pruebas manuales.
