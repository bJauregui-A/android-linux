# Backlog

Lista priorizada de lo pendiente. `NOTAS.md` es la bitácora (qué pasó); esto es **qué falta**.
Al cerrar un ítem: marcarlo `[x]`, anotar la sesión y moverlo a "Hecho" al final.

Prioridad: **P0** bloquea o deja algo a medias · **P1** validar lo que ya existe · **P2** plan vigente · **P3** escritorio completo e integración con Android · **P5** proyecto/publicación.
Juegos (Steam, Wine, mandos, DXVK) quedan **fuera por ahora**: ver "En pausa".
Origen: sesión de NOTAS (`76ª`), sección de `PROYECTO.md` o revisión del 2026-10-25.

## P0 — Cerrar lo que quedó a medias

- [ ] **B03b · Instalar desde el PC la APK armada el 25-oct** (capa y APK ya regeneradas, ver B03 en "Hecho").
- [ ] **B04 · Probar la terminal de Debian por `libldp.so`** (cambio en `AdaptadorDebianArm64.comandoTerminal` y en la consola de `SistemaActivity`, que además ahora llama `agregarEntorno`).
- [x] **B05 · Decidir qué archivos nuevos entran al repo:** `.claude/`, `.codex/`, `.gemini/`, `.agents/`, `.mcp.json`, `.vscode/`, `.graphifyignore`, `practica/`, `transcripcion_android_linux.txt`. Agregar `.codegraph/` y `graphify-out/` a `.gitignore`.
  - Hecho 25-oct: `.gitignore` actualizado con las carpetas de agentes/editor, `practica/`, la transcripción, `.codegraph/`, `graphify-out/` y `__pycache__/`.
- [x] **B06 · Poner al día `PROYECTO.md`:** "Para retomar" dice 2026-10-22; "Próximos pasos" está obsoleto (los binarios estáticos ya están, 0023). Considerar archivar las sesiones viejas de `NOTAS.md` (884 líneas).
  - Hecho 25-oct: `PROYECTO.md` al día (25-oct); falta, si se quiere, archivar sesiones viejas de `NOTAS.md`.

## P1 — Validar lo que ya existe

- [ ] **B10 · Escritorios que fallan:** el usuario probó los 14; **uno queda en negro y otro en gris** (falta anotar cuáles). Diagnosticar esos dos; los otros 12 se dan por buenos.
- [ ] **B11 · Validar los perfiles X11 directo** (`openbox`, `xfce-x11`, proveedor `x11-directo`): creados en la 74ª, sin probar en el teléfono. Ojo: OpenGL por GLX va por `mesa-gl` (drisw + readback a CPU), ver B36.
- [ ] **B12 · Instalación de Arch desde cero, de punta a punta**, con APK limpia: extracción, asistente, paquetes, primer arranque de sway, cerrar y reabrir la app.
- [ ] **B13 · Debian: `apt-get install build-essential git python3`** y compilar algo dentro (plan 76ª, punto 2).
- [ ] **B14 · Confirmar audio, portapapeles y cierre ordenado** con el usuario (quedó "falta confirmar" desde la 36ª–40ª).
- [ ] **B15 · Desbloqueo con contraseña** en Phosh/COSMIC y login SSH con la contraseña del instalador.
- [ ] **B16 · Batería de pruebas de humo automatizada** (script en el teléfono): shell, `pacman -Sy`/`apt update`, app GTK, `vkcube`, `es2gears`, audio, red virtual entre instancias, cerrar y reabrir. Base para no romper nada al seguir.
- [ ] **B17 · Prueba de binarios Go/Rust/estáticos** dentro de la batería: `rg`, `fd`, `lazygit`, un `CGO_ENABLED=0`, un musl. La capa seccomp propia (0015) y la carga de estáticos (0023) ya existen; falta una lista de programas reales que lo demuestre.

## P2 — Plan vigente (nuevas capacidades)

- [ ] **B26 · Raíz cerrada estilo chroot** (capturas del 25-oct 05:24/05:25): desde `/` de una instancia, `ls ..`, `ls /..` y `python /../dev-6918/home/user/test.py` llegan a `files/instancias/` y a **otras instancias**. Causa: `xlat()` (`android-path.c`) solo antepone `PREFIX` (`PREFIX + "/.."` = carpeta padre) y las rutas relativas van al kernel sin tocar. `cd /..` parece bien solo porque bash normaliza `$PWD` (`cd -P /..` sale). Un `chroot` real es imposible sin root (`CAP_SYS_CHROOT`). Por fases:
  1. `xlat`: normalizar `.`/`..` de las rutas absolutas y topar en `/` (arregla `/..`, `/../x`).
  2. Rutas relativas y `*at` con `dirfd`: si tienen `..`, resolverlas contra el cwd virtual (`getcwd` ya destraduce) o contra `/proc/self/fd/N`, y aplicar 1.
  3. ~~`openat2(raiz_fd, ruta, RESOLVE_IN_ROOT)`~~ **descartado** (probado el 25-oct en `dev-6918`, `Seccomp: 2`): el seccomp de apps de Android bloquea `openat2` entero, con y sin `RESOLVE_IN_ROOT` → ENOSYS. En el PC funciona. Queda todo en la glibc: además de 1 y 2, resolver los enlaces simbólicos que apunten fuera de la raíz (`readlinkat` componente a componente, solo cuando la ruta tiene `..` o pasa por un enlace absoluto).
  4. Revisar `passthrough` (`data` deja ver todo `/data/user/0/<app>/files/instancias/...`): limitarlo a lo que se usa (`/data/app` del cargador, `/data/local/tmp`).
  - Límite: es **corrección, no seguridad**. Todas las instancias tienen el mismo UID, y la `MARCA` de la capa seccomp se puede falsificar; aislar instancias de verdad pediría UIDs distintos (fuera del alcance).

- [ ] **B20 · Instancias desde Dockerfile / OCI** (plan 76ª, punto 1): intérprete de `FROM`/`ENV`/`COPY`/`RUN` e importación de tarballs OCI con la glibc propia.
- [ ] **B21 · Adaptador Ubuntu ARM64** (reusar `bootstrap-debian.py`).
- [ ] **B22 · Respaldo / exportar / restaurar una instancia** (y recuperación tras instalación fallida).
- [ ] **B23 · Actualizar el runtime sin reinstalar** (libc/capa nueva sobre instancias existentes, con respaldo `libc.so.6.00NN`).
- [ ] **B24 · SysV IPC:** colas de mensajes (`msg*`, faltan en 0008) y mover `/dev/shm/.sysv` de disco a memoria (hoy son archivos en el prefijo).
- [ ] **B25 · Rebase de los parches de glibc** a la próxima glibc de Arch ARM.

## P3 — Escritorio completo e integración con Android

Servicios D-Bus que esperan los escritorios (no hay systemd ni bus de sistema):
- [ ] **B30 · `org.freedesktop.UPower` con la batería real** (`BatteryManager` → D-Bus): la usan waybar, Plasma, XFCE y LXQt.
- [ ] **B31 · `org.freedesktop.login1` mínimo** (sesión activa, `Inhibit`, `CanSuspend`=no) para KDE, COSMIC y bloqueadores. Medir primero qué piden en los logs antes de inventar respuestas.
- [ ] **B32 · `xdg-desktop-portal` en la sesión** (`sesion-android`), con backend gtk/kde/wlr según el escritorio: selector de archivos y abrir enlaces. ScreenCast por PipeWire después.

Entrada y pantalla:
- [ ] **B33 · Captura de mouse:** `anfitrion.c` publica `zwp_pointer_constraints_v1` y `zwp_relative_pointer_v1`, pero son stubs (nunca manda `locked` ni movimiento relativo) y `WaylandActivity` no llama `requestPointerCapture()`. Conectar las dos puntas.
- [ ] **B34 · Teclado de Android de verdad:** `text-input-v3` ↔ `InputConnection` (autocorrector, predicción). Hoy `anfitrion.c` no implementa `text-input`.
- [ ] **B35 · Stylus:** `zwp_tablet_v2` con presión e inclinación (Krita, Xournal++).
- [ ] **B36 · OpenGL en X11 sin copia a CPU:** GLX va por drisw + readback (`mesa-gl/parches`). Wayland ya es cero copias; solo afecta a Xwayland y a los perfiles X11 directo.
- [ ] **B37 · Cada ventana Linux = ventana Android** (recientes, pantalla dividida, flotante).
- [ ] **B38 · Revisar si siguen pendientes:** popups xdg (menús GTK/Qt), cursor más grande, opacidad de inactivas, SUPER+V (cliphist).

Ya implementados, falta confirmar que andan en todos los escritorios:
- [ ] **B39 · Notificaciones** (`Notificar.java` + `android/android-notificaciones`), **`xdg-open` → intents** (`Abrir.java` + `android/xdg-open`) y **`/sdcard`** (`Archivos.java`).

## P5 — Proyecto y publicación

- [ ] **B50 · README público:** arquitectura, requisitos, dispositivos probados (Redmi 15 5G, Xiaomi 12T Pro), estado y límites.
- [ ] **B51 · Licencia explícita.**
- [ ] **B52 · Separar resultados medidos de objetivos**, con versiones exactas (Android, Mesa, glibc, parches) y comandos para reproducir.
- [ ] **B53 · Sección "Imposible sin root" en `PROYECTO.md`** (namespaces/`unshare`, systemd como PID 1, cgroups, módulos, KVM, ver procesos de otras apps), para filtrar propuestas que no aplican.

## Debloat

- [ ] **B60 · Checklist "Pendiente de probar"** de `NOTAS.md` (reinicio, video en Galería, links → Edge, Facebook/Messenger).
- [ ] **B61 · Limpiar la barra de estado.**

## En pausa — Juegos

Se retoman cuando P0–P3 estén estables. Detalle en `PROYECTO.md` ("Jugar") y `NOTAS.md` (14ª–17ª).
- Mandos en Wine (`winedevice.exe` cierra `event0`), vibración, varios mandos.
- Diálogos de Steam (CEF) que no toman clics.
- `winewayland.drv` o MIT-SHM sin DRI3 (evitar copia por CPU en DXVK).
- DXVK en Lutris; medir FPS reales con `DXVK_HUD`.
- Un emulador nativo ARM64 de punta a punta.

## Hecho

- [x] **B01 · Retiro de SteamOS Holo** (25-oct): sin `pacman-xfer` ni bloques muertos; las firmas de Arch ARM se verifican (sin `SigLevel = Never` global).
- [x] **B02 · Recuadros del instalador** (25-oct): ancho real de la terminal (`caja_sup/lin/med/inf`, tput/stty, 60 de respaldo).
- [x] **B03 · Capa y APK regeneradas** (25-oct): `armar.sh` + `assembleSdk36Debug`. Falta instalar: B03b.
