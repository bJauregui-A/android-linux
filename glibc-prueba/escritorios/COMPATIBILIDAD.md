# Compatibilidad de escritorios Wayland

Los perfiles de `escritorios/` son recetas para ejecutar compositores anidados en el socket
Wayland que publica Android. Que un paquete exista o que su comando esté en `sesion` no significa
que ya esté probado. `escritorio.conf` conserva `ESTADO=sin-probar` hasta validar el entorno real.

## Contrato de un perfil

- `sesion`: debe permanecer en primer plano y ejecutar el compositor con `exec`.
- El compositor debe conectarse al anfitrión usando el `WAYLAND_DISPLAY` de entrada y publicar un
  socket propio en `XDG_RUNTIME_DIR`.
- `sesion-android` registra el socket nuevo y los servicios/app lo usan en vez de asumir
  `wayland-1`. Si no aparece en 20 segundos, termina el intento y abre sway como rescate.
- `sesion-android` también inicia `autostart-android` tras detectar el socket, incluidos los
  servicios comunes que antes iniciaba sway desde su configuración.
- Las dependencias del escritorio van en `paquetes.txt`; las variables y la configuración
  específicas del compositor van en su perfil, no en `TerminalService`.

## Límites conocidos

El anfitrión Android es una superficie Wayland anidada. No ofrece DRM/KMS, sesión logind, udev
completo ni systemd de usuario. Por ello, los perfiles deben usar backend Wayland/winit anidado;
los modos DRM, TTY o sesiones que exijan logind/systemd no son compatibles sin adaptaciones.

La ruta Vulkan/Android AHardwareBuffer está implementada en el wlroots parcheado. Solo los
compositores que realmente carguen esa biblioteca aprovechan ese camino; otros pueden necesitar
renderer software o su propio soporte de buffers. Xwayland tampoco es una capacidad universal:
debe comprobarse compositor por compositor. El arranque de Steam sigue dependiendo de `DISPLAY`,
por lo que los perfiles sin Xwayland no obtienen Steam automáticamente.

## Riesgos encontrados al revisar los perfiles

- **KDE Plasma y Plasma Mobile:** `sesion` los envuelve con `dbus-run-session`. KDE avanzó hasta
  activar servicios de Plasma, pero luego cerró; los registros muestran que no hay
  `org.freedesktop.systemd1` y que el portal de documentos no puede montar por falta de permiso a
  `/dev/fuse`. Son fallos observados, no una causa confirmada del cierre de KWin. La APK de
  diagnóstico puede capturar por perfil el resultado básico de arranque.
- **COSMIC:** el perfil omite el wrapper upstream `start-cosmic` y no fija el backend anidado.
  COSMIC admite `winit` sobre Wayland, pero el perfil debe seleccionar `COSMIC_BACKEND=winit` y
  `WINIT_UNIX_BACKEND=wayland`; faltan probar además sus servicios de sesión sin systemd de usuario.
- **Niri y COSMIC:** usan backend anidado EGL. Su inicio puede fallar si la EGL disponible no
  implementa `EGL_WL_bind_wayland_display`; la disponibilidad de esa extensión no está comprobada
  en esta instalación.
- **labwc, Wayfire, Phosh, River, Qtile, XFCE y LXQt:** comparten wlroots, renderer Vulkan y la
  biblioteca parcheada. El backend Wayland se elige automáticamente al heredar `WAYLAND_DISPLAY`,
  pero el resto depende de que sus versiones sean ABI compatibles con `libwlroots-0.20.so` y de
  que cada compositor soporte el renderer parcheado. No hay todavía evidencia de ejecución para
  estos perfiles.
- **LXQt:** `startlxqtwayland` inicia el compositor configurado en `~/.config/lxqt/session.conf`;
  `labwc` está configurado allí. La sesión y su panel aún no se han probado.
- **Weston:** usa su backend Wayland anidado, pero la escala se redondea al entero más cercano
  (`2.5` pasa a `3`); puede quedar sobredimensionado aunque el compositor arranque.

## Validación pendiente

Probar en el dispositivo, perfil por perfil: arranque anidado y socket, presentación, tacto/teclado,
escala y giro, clientes Wayland, portapapeles, audio y Xwayland cuando aplique. Marcar `probado`
solo después de confirmar esos puntos. No se deben considerar probados KDE, COSMIC, Weston, niri,
Phosh ni los demás perfiles solo por tener receta de arranque. El barrido de la APK solo confirma
que apareció un socket y el proceso siguió vivo tres segundos; no reemplaza las pruebas manuales.
