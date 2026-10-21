# Contrato de escritorios y proveedores de pantalla

Los perfiles de `escritorios/` describen sesiones y los proveedores de
`escritorios/proveedores/` describen cómo conectarlas a una pantalla. Son capas independientes:
que un paquete exista o que su comando esté en `sesion` no significa que ya esté probado.
`escritorio.conf` conserva `ESTADO=sin-probar` hasta validar el entorno real.

## Contrato del perfil (`escritorio.conf`)

- `PROVEEDOR_PANTALLA`: ID del proveedor requerido.
- `REQUISITOS_SESION`: requisitos separados por espacios, por ejemplo `dbus-session wayland`.
- `CAPACIDADES_REQUERIDAS`: capacidades que debe ofrecer el proveedor.
- `READY_LEVEL`: etapa que declara el perfil. `proveedor-y-proceso` solo significa que el proveedor
  pasó su comprobación y que el proceso del perfil sigue vivo; no acredita presentación, entrada ni
  interactividad.
- `sesion`: inicia los procesos del perfil en primer plano; normalmente termina con `exec`.
- `paquetes.txt`, `home/` y `ESTADO`: dependencias, configuración inicial y nivel de validación.

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

## Ciclo común

- `sesion-android` carga los contratos del perfil y proveedor, valida los requisitos y arranca el
  perfil con las variables declaradas por el proveedor.
- Al superar readiness, publica el endpoint y lanza los servicios comunes. Si falla, termina el
  intento y abre sway como rescate (hasta que el rescate también sea configurable).
- `sesion-android` también inicia `autostart-android` tras detectar el socket, incluidos los
  servicios comunes que antes iniciaba sway desde su configuración.
- `sesion-android` crea un único bus D-Bus de sesión, publica su dirección y actualiza el entorno
  de activación cuando ya conoce `WAYLAND_DISPLAY`. KDE/Plasma Mobile usan este mismo bus.
- `autostart-android` supervisa los procesos de servicio que inicia. Al cerrar solicita primero
  el cierre ordenado de Steam por sway IPC cuando está disponible y luego detiene esos procesos.
- Las dependencias van en `paquetes.txt`; las variables del perfil están en su receta y las de
  conexión/readiness en el proveedor, no en `TerminalService`.

## Límites conocidos

El anfitrión Android actual ofrece una superficie Wayland anidada. No ofrece DRM/KMS, sesión
logind, udev completo ni systemd de usuario. Los perfiles activos declaran Wayland; modos DRM, TTY
o sesiones que exijan logind/systemd no son compatibles sin adaptaciones. La arquitectura acepta
otros proveedores, pero eso no significa que estén implementados.

La ruta Vulkan/Android AHardwareBuffer está implementada en el wlroots parcheado. Solo los
compositores que realmente carguen esa biblioteca aprovechan ese camino; otros pueden necesitar
renderer software o su propio soporte de buffers. Xwayland tampoco es una capacidad universal:
debe comprobarse compositor por compositor. El arranque de Steam sigue dependiendo de `DISPLAY`,
por lo que los perfiles sin Xwayland no obtienen Steam automáticamente.

## Riesgos encontrados al revisar los perfiles

- **KDE Plasma y Plasma Mobile:** usan el bus común de `sesion-android`. KDE avanzó hasta activar
  servicios de Plasma, pero luego cerró; los registros muestran que no hay
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
