# Backlog

Lista priorizada de lo pendiente. `NOTAS.md` es la bitácora (qué pasó); esto es **qué falta**.
**Orden del archivo: 1) Por hacer · 2) En pausa · 3) Hecho.** Al cerrar un ítem: quitarlo de "Por hacer", añadirlo a "Hecho" con fecha y commit/evidencia (y marcar `[x]`). Si solo se avanzó, dejarlo abierto con una línea de "Avance".

Prioridad: **P0** bloquea o deja algo a medias · **P1** validar lo que ya existe · **P2** plan vigente · **P3** escritorio completo e integración con Android · **P5** proyecto/publicación.
Juegos (Steam, Wine, mandos, DXVK) quedan **fuera por ahora**: ver "En pausa".
Origen: sesión de NOTAS (`76ª`), sección de `PROYECTO.md` o revisión del 2026-10-25. Última puesta al día: 2026-10-25.

# 1. Por hacer

### P0 — Cerrar lo que quedó a medias

- [ ] **B04 · Probar la terminal de Debian por `libldp.so`** (cambio en `AdaptadorDebianArm64.comandoTerminal` y en la consola de `SistemaActivity`, que además ahora llama `agregarEntorno`).

### P1 — Validar lo que ya existe

- [ ] **B10 · Escritorios que fallan:** el usuario probó los 14; **uno queda en negro y otro en gris** (falta anotar cuáles). Diagnosticar esos dos; los otros 12 se dan por buenos.
- [ ] **B11 · Validar los perfiles X11 directo** (`openbox`, `xfce-x11`, proveedor `x11-directo`): creados en la 74ª, sin probar en el teléfono. Ojo: OpenGL por GLX va por `mesa-gl` (drisw + readback a CPU), ver B36.
- [ ] **B12 · Instalación de Arch desde cero, de punta a punta**, con APK limpia: extracción, asistente, paquetes, primer arranque de sway, cerrar y reabrir la app.
  - Avance 25-oct (instancia `h-39198`, LXQt): extracción, asistente, `pacman -Syu` de los paquetes, `pacman -Sy` con firmas, sesión y `sshd` READY ✔. Falta: probar con sway, cerrar y reabrir la app, y APK limpia (sin datos previos).
- [ ] **B13 · Debian: `apt-get install build-essential git python3`** y compilar algo dentro (plan 76ª, punto 2).
- [ ] **B18 · `groupadd`/`useradd` fallan (Debian y Arch)**: al instalar `apache2` en `deb-54462` (25-oct), el `postinst` de `ssl-cert` murió con `groupadd: /etc/group.25612: lock file already used (nlink: 1)`. El bloqueo de shadow hace `link(archivo.PID, archivo.lock)` y exige `st_nlink == 2`; como Android no deja crear enlaces duros, `linkat` en `android-path.c:527` **copia**, y el nlink queda en 1. Afecta a cualquier paquete que cree usuarios o grupos (`adduser`, `systemd-sysusers`...). Hoy se esquiva poniendo de antemano los usuarios en la base (`sshd`, `_ssh`), pero no escala. Opciones: que la copia de `linkat` sobre `*.lock` informe `st_nlink = 2` (marca en un xattr `user.*`), o que el bloqueo use otro camino. Reparar después con `dpkg --configure -a`.
- [ ] **B19 · Debian sin usrmerge real:** en `deb-54462`, `/bin`, `/sbin` y `/lib` son carpetas, no enlaces a `usr/` (se instaló `usr-is-merged` para que apt no se queje). Bookworm deja las unidades en `/lib/systemd/system`, y `service-daemon.c` solo lee `/usr/lib/systemd/system`, así que `apache2.service` y `ssh.service` no se ven. Hacer el merge real en `bootstrap-debian.py` (`bin → usr/bin`, `lib → usr/lib`, `sbin → usr/sbin`), que además deja de necesitar los enlaces cruzados de `instalar.sh`. Mientras tanto, conviene que el supervisor lea también `/lib/systemd/system`.
- [ ] **B19b · Mensaje final del instalador en "Sin Entorno":** dice "Iniciando el entorno de escritorio en la pantalla..." aunque no hay escritorio.
- [ ] **B14 · Confirmar audio, portapapeles y cierre ordenado** con el usuario (quedó "falta confirmar" desde la 36ª–40ª). `sshd` ya confirmado el 25-oct (ver Hecho).
- [ ] **B15 · Desbloqueo con contraseña** en Phosh/COSMIC y login SSH con la contraseña del instalador.
- [ ] **B16 · Batería de pruebas de humo automatizada** (script en el teléfono): shell, `pacman -Sy`/`apt update`, app GTK, `vkcube`, `es2gears`, audio, red virtual entre instancias, cerrar y reabrir. Base para no romper nada al seguir.
- [ ] **B17 · Prueba de binarios Go/Rust/estáticos** dentro de la batería: `rg`, `fd`, `lazygit`, un `CGO_ENABLED=0`, un musl. La capa seccomp propia (0015) y la carga de estáticos (0023) ya existen; falta una lista de programas reales que lo demuestre.

- [ ] **B40 · `ss` (y otras herramientas de diagnóstico) dan `Cannot open netlink socket: Permission denied`:** la glibc solo emula Netlink de rutas (0020/0021: `ip a`, `ip r`, `ip link`, `ip neigh`); falta `NETLINK_SOCK_DIAG`/`inet_diag` para `ss`. Alternativa mínima: leer `/proc/net/tcp*` (lo que `ss` hace sin netlink con `-O`/fallback) o dar un `ss` propio.
- [ ] **B41 · Menú de escritorios (`primer-arranque.sh`) hace `( . escritorio.conf )` en un subproceso por fila y por redibujo:** leer los `.conf` una sola vez al abrir el menú (arrays) para que ande más fluido.
- [ ] **B42 · Entender por qué un `connect` a `127.0.0.1:<puerto de la instancia>` no llega:** es consecuencia de 0022 (la IP virtual `10.0.0.N` ↔ `127.0.0.N`, `bind 0.0.0.0` → `127.0.0.N`). Documentar en `PROYECTO.md` ("Red virtual") que los servicios de una instancia se alcanzan en su IP virtual y, desde el PC, por el proxy de puertos; y revisar que `adb forward` + `proxy-puertos` llegue a `sshd` (probado solo dentro de la instancia).

### P2 — Plan vigente (nuevas capacidades)

- [ ] **B26b · Achicar `passthrough`** (`/data` deja ver `/data/user/0/<app>/files/instancias/...` por ruta completa). Inventariar antes qué usa `/data` (cargador en `/data/app`, `/data/local/tmp/proxy-ports.conf`, `adb-puerto`...). Depende de B26 (hecho).
- [ ] **B43 · Instalar la libc 0025 en las demás instancias y regresión con escritorio.** `scripts/instalar-libc-en-instancia.sh <id>` (con `--revertir`); probar sway, kitty, `sshd`, `sudo` en una sesión real. Solo `dev-6918` y `deb-54462` la tienen.
- [ ] **B28 · Enlaces simbólicos independientes del prefijo.** Hoy `symlinkat` guarda el destino absoluto con la ruta real (`/data/user/0/<app>/files/instancias/<id>/usr/...`) y `readlinkat` le quita el prefijo al leerlo. Si la instancia se copia, se renombra o se restaura (B22), esos enlaces se rompen. Ya pasa: en `dev-6918` hay 4 enlaces rotos que apuntan al prefijo viejo `files/archlinux/` (por ejemplo `usr/lib/libkeyutils.so`). Propuesta: guardar el destino **relativo** a la carpeta del enlace (`/usr/lib/x` desde `/usr/lib/y` → `x`), que el kernel resuelve dentro del prefijo; o guardar el destino de Linux tal cual y que la glibc resuelva los enlaces absolutos (más caro). Incluir un script que repare los enlaces de las instancias existentes.
- [ ] **B27 · Usuarios y permisos virtuales en la glibc** (propuesta del 25-oct; **diseño en `glibc-prueba/ARQUITECTURA-USUARIOS.md`**, con fases y criterios de aceptación). Hoy hay un solo UID real: `GLIBC_FAKEROOT=1` hace que `getuid` dé 0, los `set*id` se aceptan sin efecto (0010) y `stat` muestra el UID de la app. Objetivo: que `sudo`, `useradd`, `chown`, `chmod` y los demonios que bajan privilegios (sshd, apache con `www-data`, postgres) **oficiales** funcionen como en Linux, sin wrappers. Piezas:
  1. **Credenciales virtuales por proceso** (uid/euid/suid, gid, grupos): `set*id`/`get*id` las cambian de verdad en la glibc; se heredan en `fork` y viajan por `execve` (variable de entorno interna o en el auxv del cargador).
  2. **Dueño y modo virtuales por archivo** en un xattr `user.*` (viaja con el archivo en `rename`, sin base de datos aparte). `stat`/`statx` devuelven el valor virtual; `chown`/`chmod` lo escriben. Sin xattr: dueño por regla (root fuera de `/home/<usuario>`). Los archivos nuevos toman el uid efectivo del que los crea.
  3. **Bit setuid virtual en `execve`**: un ejecutable con setuid virtual de root pasa el euid a 0. Así funciona el `sudo` real (con PAM y `/etc/sudoers`), y se puede retirar el wrapper.
  4. **Chequeo de permisos opcional** en `open`/`access`/`execve` según el modo virtual, para que se vean los errores normales de Linux. Es semántica, **no seguridad**: el UID real es uno solo.
  5. **Bloqueo de shadow** (B18): con la misma infraestructura de xattr, la copia de `linkat` sobre `*.lock` informa `st_nlink = 2`. Así funcionan `useradd`, `groupadd` y `passwd` oficiales; `/etc/passwd`, `group` y `shadow` siguen siendo la única base de usuarios.
  6. **App** (después): lista de usuarios de la instancia, usuario por defecto de la terminal, cambiar contraseña.
  - Probado el 25-oct en `dev-6918`: xattrs `user.*` ✅ en archivos y carpetas, se conservan en `rename`; en symlinks EPERM (normal en Linux). Al verse como root, los programas intentan `chroot` (sshd privsep): depende de B26. Costo: un `getxattr` extra en cada `stat`. Referencias: `pseudo` (Yocto) y `fakeroot -s` resuelven lo mismo con base de datos.

- [ ] **B20 · Instancias desde Dockerfile / OCI** (plan 76ª, punto 1): intérprete de `FROM`/`ENV`/`COPY`/`RUN` e importación de tarballs OCI con la glibc propia.
- [ ] **B21 · Adaptador Ubuntu ARM64** (reusar `bootstrap-debian.py`).
- [ ] **B22 · Respaldo / exportar / restaurar una instancia** (y recuperación tras instalación fallida).
- [ ] **B23 · Actualizar el runtime sin reinstalar** (libc/capa nueva sobre instancias existentes, con respaldo `libc.so.6.00NN`).
- [ ] **B24 · SysV IPC:** colas de mensajes (`msg*`, faltan en 0008) y mover `/dev/shm/.sysv` de disco a memoria (hoy son archivos en el prefijo).
- [ ] **B25 · Rebase de los parches de glibc** a la próxima glibc de Arch ARM.

### P3 — Escritorio completo e integración con Android

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

### P5 — Proyecto y publicación

- [ ] **B50 · README público:** arquitectura, requisitos, dispositivos probados (Redmi 15 5G, Xiaomi 12T Pro), estado y límites.
- [ ] **B51 · Licencia explícita.**
- [ ] **B52 · Separar resultados medidos de objetivos**, con versiones exactas (Android, Mesa, glibc, parches) y comandos para reproducir.
- [ ] **B53 · Sección "Imposible sin root" en `PROYECTO.md`** (namespaces/`unshare`, systemd como PID 1, cgroups, módulos, KVM, ver procesos de otras apps), para filtrar propuestas que no aplican.

### Debloat

- [ ] **B60 · Checklist "Pendiente de probar"** de `NOTAS.md` (reinicio, video en Galería, links → Edge, Facebook/Messenger).
- [ ] **B61 · Limpiar la barra de estado.**

# 2. En pausa

## Juegos

Se retoman cuando P0–P3 estén estables. Detalle en `PROYECTO.md` ("Jugar") y `NOTAS.md` (14ª–17ª).
- Mandos en Wine (`winedevice.exe` cierra `event0`), vibración, varios mandos.
- Diálogos de Steam (CEF) que no toman clics.
- `winewayland.drv` o MIT-SHM sin DRI3 (evitar copia por CPU en DXVK).
- DXVK en Lutris; medir FPS reales con `DXVK_HUD`.
- Un emulador nativo ARM64 de punta a punta.

# 3. Hecho

Más reciente primero. Detalle de cada sesión en `NOTAS.md`.

## 25-oct-2026

- [x] **B26 · Raíz cerrada estilo chroot** (parche `0025-android-raiz-cerrada.patch`; historia `historias/B26-raiz-cerrada.md`): `ls ..`, `ls /..`, `cat /../<otra>/...`, `os.listdir('/..')` y `execveat` con `dirfd` ya no salen de la instancia, también en binarios estáticos. Evidencia: `pruebas/raiz/salidas/` (rojo con la libc anterior, verde en Arch y Debian), `test.sh` en el PC. Instalado en `dev-6918` y `deb-54462`. **Avance pendiente:** instalar la libc en las otras 6 instancias; regresión con escritorio (sway/kitty/`sshd`/`sudo`). Sigue abierto **B26b** (abajo).
- [x] **B29 · Correr pruebas dentro de la app desde el PC** (`scripts/probar-en-telefono.sh`, `ReceptorPruebas` en `src/debug/`, acción `EJECUTAR_PRUEBA`): corre con el seccomp real y devuelve salida y código. Autoprueba verde (`pruebas/intent/salidas/`). **Límite:** necesita una sesión de la app viva; sin ella HyperOS responde `proc frequent died` y el script sale con 3.

- [x] **B01 · Retiro de SteamOS Holo y pacman como antes de Holo** (`06101ce`, `77908e7`): sin `[holo-*]`, `pacman-xfer` ni `XferCommand`; `bootstrap.py` idéntico al de `69c84a8` (`IgnorePkg = glibc`, sin `HoldPkg` extra, `SigLevel` de la plantilla: firmas de Arch ARM verificadas). Verificado en instancias nuevas: `pacman.conf` correcto y `pacman -Sy` OK.
- [x] **B02 · Recuadros del instalador al ancho real de la terminal** (`06101ce`…`3759118`). `instalar.sh` (sh de Android) y `primer-arranque.sh` (bash) miden el ancho una vez (`stty size </dev/tty`, `tput`, `COLUMNS`, 60) y de nuevo con SIGWINCH; el texto largo se pliega y las filas de menú se cortan con «…». `primer-arranque.sh` usa bash puro, sin procesos hijos (menús rápidos). Probado a 54 columnas en el Redmi.
- [x] **B03 · Capa y APK regeneradas e instaladas** (varias veces, última `551bb0d`): `armar.sh` (con `$Z` corregido) + `assembleSdk36Debug` + `adb install -r`.
- [x] **B07 · Instalador arreglado tras las pruebas en el teléfono:** `_ancho` ya no aborta con `set -e` cuando falta `tput` (`7594b8d`); `TMPDIR=$P/tmp` para los heredocs de mksh (`1c32edd`); el conteo de columnas UTF-8 usa el `tr` de Android con bytes reales (`3759118`); `stty` ya no se mide dentro de pipes (`e450155`).
- [x] **B08 · `sshd` arranca solo en la sesión** (`551bb0d`, confirmado por el usuario: "ssh ready"): el chequeo de `autostart-android` conectaba a `127.0.0.1:8022`, pero la glibc (0022) mapea la IP virtual de la instancia a `127.0.0.N` y `sshd` escucha ahí; ahora conecta a `/etc/virtual-ip`. `sshd` se lanza con `-e` (errores a su log).
- [x] **B05 · Carpetas de agentes/editor fuera del repo** (`a75ff9a`): `.gitignore` con `.agents/`, `.claude/`, `.codex/`, `.gemini/`, `.mcp.json`, `.vscode/`, `.graphifyignore`, `.codegraph/`, `graphify-out/`, `practica/`, `transcripcion_android_linux.txt`, `__pycache__/`.
- [x] **B06 · `PROYECTO.md` al día** (`a75ff9a`): estado 2026-10-25, filas de pacman e instalador adaptativo, "Próximos pasos" apunta a este archivo. (Archivar sesiones viejas de `NOTAS.md` es opcional y quedó sin hacer.)
