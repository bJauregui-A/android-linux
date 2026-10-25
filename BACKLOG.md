# Backlog

Lista priorizada de lo pendiente. `NOTAS.md` es la bitácora (qué pasó); esto es **qué falta**.
**Orden del archivo: 1) Por hacer · 2) En pausa · 3) Hecho.** Al cerrar un ítem: quitarlo de "Por hacer", añadirlo a "Hecho" con fecha y commit/evidencia (y marcar `[x]`). Si solo se avanzó, dejarlo abierto con una línea de "Avance".

Prioridad: **P0** bloquea o deja algo a medias · **P1** validar lo que ya existe · **P2** plan vigente · **P3** escritorio completo e integración con Android · **P5** proyecto/publicación.
Juegos (Steam, Wine, mandos, DXVK) quedan **fuera por ahora**: ver "En pausa".
Origen: sesión de NOTAS (`76ª`), sección de `PROYECTO.md` o revisión del 2026-10-25. Última puesta al día: 2026-10-25 (80ª).

# 1. Por hacer

### P0 — Cerrar lo que quedó a medias

- [ ] **B04 · Probar la terminal de Debian por `libldp.so`** (cambio en `AdaptadorDebianArm64.comandoTerminal` y en la consola de `SistemaActivity`, que además ahora llama `agregarEntorno`).

### P1 — Validar lo que ya existe

- [ ] **B10 · Escritorios que fallan:** el usuario probó los 14; **uno queda en negro y otro en gris** (falta anotar cuáles). Diagnosticar esos dos; los otros 12 se dan por buenos.
- [ ] **B11 · Validar los perfiles X11 directo** (`openbox`, `xfce-x11`, proveedor `x11-directo`): creados en la 74ª, sin probar en el teléfono. Ojo: OpenGL por GLX va por `mesa-gl` (drisw + readback a CPU), ver B36.
- [ ] **B12 · Instalación de Arch desde cero, de punta a punta**, con APK limpia: extracción, asistente, paquetes, primer arranque de sway, cerrar y reabrir la app.
  - Avance 25-oct (instancia `h-39198`, LXQt): extracción, asistente, `pacman -Syu` de los paquetes, `pacman -Sy` con firmas, sesión y `sshd` READY ✔. Falta: probar con sway, cerrar y reabrir la app, y APK limpia (sin datos previos).
- [ ] **B13 · Debian: `apt-get install build-essential git python3`** y compilar algo dentro (plan 76ª, punto 2).
- [x] **B18 · `groupadd`/`useradd` fallan (Debian y Arch)**: al instalar `apache2` en `deb-54462` (25-oct), el `postinst` de `ssl-cert` murió con `groupadd: /etc/group.25612: lock file already used (nlink: 1)`. El bloqueo de shadow hace `link(archivo.PID, archivo.lock)` y exige `st_nlink == 2`; como Android no deja crear enlaces duros, `linkat` en `android-path.c:527` **copia**, y el nlink queda en 1. Afecta a cualquier paquete que cree usuarios o grupos (`adduser`, `systemd-sysusers`...). Hoy se esquiva poniendo de antemano los usuarios en la base (`sshd`, `_ssh`), pero no escala. Opciones: que la copia de `linkat` sobre `*.lock` informe `st_nlink = 2` (marca en un xattr `user.*`), o que el bloqueo use otro camino. Reparar después con `dpkg --configure -a`.
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
- [ ] **B44 · Validar el nombre de instancia.** El nombre "." generó el id `--67263` (empieza con guiones: rompe `ls`, `grep`, scripts). Limpiar el id (solo `[a-z0-9_-]`, sin guion inicial) y rechazar nombres vacíos o de puntos.
- [ ] **B45 · Autoprueba de instancias nuevas.** Que `pruebas/intent/` cree (o reciba) una instancia Arch y una Debian y compruebe que la libc cargada tiene el hash de `glibc/salida` y que `ls /..` no sale. Evita repetir lo de la Debian con la libc vieja (`armar.sh` no rehacía `base-debian.tgz`).
- [ ] **B46 · `sudo -n` no funciona.** El wrapper `/usr/local/bin/sudo` (fakeroot) no acepta `-n` (`exec: -n: invalid option`); aceptar y ignorar `-n`/`-S`/`-k`/`-H` y revisar `sudo -l`.
- [ ] **B47 · Causa de la raíz en 555.** La raíz de las Arch nuevas quedaba en `dr-xr-xr-x` (las viejas en 777). Se parchó al abrir la instancia (`TerminalService.entorno`); falta saber qué la deja así (¿un paquete de la base nueva?) y arreglarla en origen.
- [ ] **B48 · Pruebas del supervisor en el repo.** La prueba con `SERVICE_ROOT` (rootfs Debian falso: alias, `enable`/`disable`, `EnvironmentFile`, `ExecStartPre`, `logs`, nombre inexistente, `list -a`) se hizo a mano en el scratchpad y no quedó guardada. Dejarla en `pruebas/supervisor/test.sh` (corre en el PC con `compilar.sh --local`); ojo: el cliente lanza el demonio con `argv[0]` corto, así que `pkill -f <ruta>` no lo encuentra (usar `SERVICE_DAEMON` y matar por PID).
- [ ] **B49 · Sincronizar la capa a instancias existentes.** El APK solo aplica `capa.tgz` al crear una instancia: `service`, `sv`, `service-daemon` y `autostart-android` se copiaron a mano con `run-as` a 4 instancias (hoy borradas: el 25-oct el usuario las eliminó todas). Hacer `scripts/sincronizar-capa-en-instancia.sh <instancia>` (respaldo y `--revertir`, `cp`+`mv` por si el binario está en uso), como `instalar-libc-en-instancia.sh`.
- [ ] **B50 · Un servicio que falla al arrancar atasca el demonio.** `servicios_revisar_hijos` hace `usleep(500000)` y reinicia en el mismo hilo: un servicio que muere al instante (p. ej. sshd con el puerto ocupado) deja al demonio reiniciando sin parar y a los clientes esperando. Reinicio con espera no bloqueante, límite de reintentos y estado `failed`.
- [ ] **B51 · Log de sshd.** Con `-D -e` el `stderr` de sshd queda en `/dev/null` (fd 2) y `service logs ssh` solo muestra las líneas `INICIO`; con `-E /var/log/supervisor/ssh.log` sí escribe. Estaba puesto solo a mano en una Debian que ya no existe; la Debian nueva (`debian_console-44800`) no lo trae. Averiguar por qué sshd descarta `stderr` y fijar el valor en el instalador de Debian.
- [ ] **B52 · Un solo dueño para sshd.** Lo arrancan dos caminos: `autostart-android` (si `ssh`/`sshd` no está en `enabled.txt`) y el supervisor (si está habilitado). Que `autostart-android` delegue siempre en `service` y no lance sshd él mismo.

- [ ] **B28 · Enlaces simbólicos independientes del prefijo.** Hoy `symlinkat` guarda el destino absoluto con la ruta real (`/data/user/0/<app>/files/instancias/<id>/usr/...`) y `readlinkat` le quita el prefijo al leerlo. Si la instancia se copia, se renombra o se restaura (B22), esos enlaces se rompen. Ya pasa: en `dev-6918` hay 4 enlaces rotos que apuntan al prefijo viejo `files/archlinux/` (por ejemplo `usr/lib/libkeyutils.so`). Propuesta: guardar el destino **relativo** a la carpeta del enlace (`/usr/lib/x` desde `/usr/lib/y` → `x`), que el kernel resuelve dentro del prefijo; o guardar el destino de Linux tal cual y que la glibc resuelva los enlaces absolutos (más caro). Incluir un script que repare los enlaces de las instancias existentes.
- [ ] **B27 · Usuarios y permisos virtuales en la glibc** (propuesta del 25-oct; **diseño en `glibc-prueba/ARQUITECTURA-USUARIOS.md`**, con fases y criterios de aceptación). Hoy hay un solo UID real: `GLIBC_FAKEROOT=1` hace que `getuid` dé 0, los `set*id` se aceptan sin efecto (0010) y `stat` muestra el UID de la app. Objetivo: que `sudo`, `useradd`, `chown`, `chmod` y los demonios que bajan privilegios (sshd, apache con `www-data`, postgres) **oficiales** funcionen como en Linux, sin wrappers. Piezas:
  1. **Credenciales virtuales por proceso** (uid/euid/suid, gid, grupos): `set*id`/`get*id` las cambian de verdad en la glibc; se heredan en `fork` y viajan por `execve` (variable de entorno interna o en el auxv del cargador).
  2. **Dueño y modo virtuales por archivo** en un xattr `user.*` (viaja con el archivo en `rename`, sin base de datos aparte). `stat`/`statx` devuelven el valor virtual; `chown`/`chmod` lo escriben. Sin xattr: dueño por regla (root fuera de `/home/<usuario>`). Los archivos nuevos toman el uid efectivo del que los crea.
  3. **Bit setuid virtual en `execve`**: un ejecutable con setuid virtual de root pasa el euid a 0. Así funciona el `sudo` real (con PAM y `/etc/sudoers`), y se puede retirar el wrapper.
  4. **Chequeo de permisos opcional** en `open`/`access`/`execve` según el modo virtual, para que se vean los errores normales de Linux. Es semántica, **no seguridad**: el UID real es uno solo.
  5. **Bloqueo de shadow** (B18): con la misma infraestructura de xattr, la copia de `linkat` sobre `*.lock` informa `st_nlink = 2`. Así funcionan `useradd`, `groupadd` y `passwd` oficiales; `/etc/passwd`, `group` y `shadow` siguen siendo la única base de usuarios.
  6. **App** (después): lista de usuarios de la instancia, usuario por defecto de la terminal, cambiar contraseña.
  - **Siguiente: fase 3** (setuid virtual en `execve` + `sudo` real, sin wrapper).
  - **Avance 25-oct (80ª): fase 1 hecha** (parche 0026: credenciales virtuales, `stat` con dueño virtual, `GLIBC_CRED` por `execve`; `pruebas/cred/test.sh` 8/8 en Arch y Debian). Falta la fase 2 en adelante. Se conserva el UID real de la app como usuario principal.
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

- [ ] **B53 · Sección "Imposible sin root" en `PROYECTO.md`** (namespaces/`unshare`, systemd como PID 1, cgroups, módulos, KVM, ver procesos de otras apps), para filtrar propuestas que no aplican.
- [ ] **B54 · README público:** arquitectura, requisitos, dispositivos probados (Redmi 15 5G, Xiaomi 12T Pro), estado y límites.
- [ ] **B55 · Licencia explícita.**
- [ ] **B56 · Separar resultados medidos de objetivos**, con versiones exactas (Android, Mesa, glibc, parches) y comandos para reproducir.

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

- [x] **B43 · Libc 0025/0026 en instancias viejas:** ya no aplica. Las instancias anteriores se borraron (25-oct, a pedido); las nuevas (`arch_console-47028`, `debian_console-44800`) traen la libc de la APK. Sigue pendiente la regresión de Debian **con escritorio**.
- [x] **B27 fase 1 · Credenciales virtuales y dueño virtual en `stat` (80ª sesión):** parche `0026-android-credenciales-virtuales.patch`; `get*id`/`set*id`/`setgroups`/`getgroups`/`setfs*id` con reglas de Linux, herencia por `fork` y `execve` (`GLIBC_CRED`), `GLIBC_FAKEROOT=1` = root; `stat` por xattr `user.linux.owner` o por ubicación. Evidencia: `pruebas/cred/test.sh` 8/8 en `arch_console-47028` y `debian_console-44800`; costo de `stat` +33–37 %. APK con la libc 0026 instalada el 25-oct (respaldo de la anterior en `~/respaldos-apk/*-antes-credenciales/`). Sigue abierto B27 (fases 2–5).
- [x] **B27 fase 2 · `chown` persistente, dueño de archivos nuevos y cerrojo de shadow (81ª sesión):** parche `0027-android-dueno-persistente.patch`; `chown`/`fchown`/`fchownat` de root virtual guardan el dueño en `user.linux.owner` (se borra si coincide con la regla), `openat O_CREAT`/`mkdirat`/`mknodat` de un proceso con fsuid distinto del principal escriben el dueño nuevo, y las copias de `linkat` quedan marcadas (`user.linux.par`) para que `stat` dé `st_nlink = 2`. **Cierra B18.** Pruebas: `pruebas/dueno/dentro.sh` (26 casos, 0 fallas en Arch y Debian). Criterio cumplido: `groupadd`, `useradd -m`, `userdel -r` y `apt install apache2` + `dpkg --configure -a` limpios en Debian. Pendiente aparte: el Debian de la app no trae `www-data` ni el resto de usuarios de `base-passwd` (falta `hostname` también) — ver B53. **APK con la libc 0027 instalada** (`adb install -r`, instancias intactas).
- [x] **B27 fase 3 · setuid virtual y `sudo` real (82ª sesión):** parche `0028-android-setuid-virtual.patch`; `execve` aplica setuid/setgid del modo real con el dueño virtual, y root salta el permiso de escritura al abrir. `sudo` real (paquete instalado en el primer arranque, regla con contraseña, wrapper retirado). Evidencia: `pruebas/suid` y `pruebas/sudo` 0 fallas en Arch y Debian; APK nueva instalada el 25-oct; falta probar el primer arranque de una instancia nueva.
- [ ] **B27 fase 4 · Operaciones de root (pendiente, próxima sesión):** base ya hecha: B26 (raíz cerrada, parche 0025) y `chroot("/")` como no-op; cualquier otro `chroot(dir)` sigue dando EPERM. Falta: (1) `chroot(dir)` virtual por proceso (prefijo `PREFIX + dir`, heredado y viajando por `execve` como `GLIBC_PREFIX`) para sshd con privsep, vsftpd, postfix; (2) `PR_SET_KEEPCAPS`, `capset`/`capget` y `PR_CAPBSET_*` virtuales (`setpriv --reuid` hoy exige bajar primero el gid); (3) `setrlimit` sobre el tope duro recordado; (4) `mount`/`unshare`/`setns` con EPERM. Criterio: `sshd` lanzado por el supervisor como root con privsep; apache con workers como `www-data`. Antes, probar el primer arranque de una instancia nueva con la APK de la fase 3 (instalada el 25-oct) y B53 (Debian sin `nobody`/`www-data`). Pendientes menores: `no_new_privs`, `chown` no limpia setuid/setgid, bit setgid de carpetas, root salta permisos de carpetas/lectura (fase 5).

- [x] **Supervisor modular, sintaxis `service <acción> <nombre>` y SSH en Debian (79ª sesión):** `supervisor/` partido en módulos; se quitó el orden antiguo `service <nombre> <acción>`; el demonio busca unidades también en `/lib/systemd/system` (Debian sin usr-merge) y resuelve alias (`ssh`/`sshd`/`openssh-server`); `service logs` funciona (antes el demonio no tenía el comando); `autostart-android` encuentra `sshd` en `/usr/sbin` (Debian) y no lo duplica si `ssh` está habilitado; las sesiones ssh de Debian llevan `LD_LIBRARY_PATH` (`SetEnv` en `20-debian-libs.conf`, también en `apk/instalar.sh`). APK instalada (15:12) y probado por el usuario: ssh a Debian entra. Detalle en `NOTAS.md` (79ª).

- [x] **Instalador y pruebas con instancias nuevas (78ª sesión):** Debian ya sale con la libc 0025 (`armar.sh` rehace `base-debian.tgz` si la glibc es más nueva); al terminar la instalación sin gráficos abre la terminal (no el inicio) y la barra dice SALIR; el menú de escritorios ya no tiene "Confirmar y continuar" (antes elegía `sin-entorno` sin querer); `/` queda escribible en Arch (`sudo mkdir /x` funciona); mensaje final correcto en consola; `probar-en-telefono.sh` acepta ids con guiones iniciales. Detalle en `NOTAS.md` (78ª). Abiertos: B44–B47 y B43.

- [x] **B26 · Raíz cerrada estilo chroot** (parche `0025-android-raiz-cerrada.patch`; historia `historias/B26-raiz-cerrada.md`): `ls ..`, `ls /..`, `cat /../<otra>/...`, `os.listdir('/..')` y `execveat` con `dirfd` ya no salen de la instancia, también en binarios estáticos. Evidencia: `pruebas/raiz/salidas/` (rojo con la libc anterior, verde en Arch y Debian), `test.sh` en el PC. Las instancias nuevas ya la traen (probado en Arch y Debian). **Pendiente:** regresión con escritorio (sway/kitty/`sshd`/`sudo`) y libc en instancias viejas (B43). Sigue abierto **B26b** (abajo).
- [x] **B29 · Correr pruebas dentro de la app desde el PC** (`scripts/probar-en-telefono.sh`, `ReceptorPruebas` en `src/debug/`, acción `EJECUTAR_PRUEBA`): corre con el seccomp real y devuelve salida y código. Autoprueba verde (`pruebas/intent/salidas/`). **Límite:** necesita una sesión de la app viva; sin ella HyperOS responde `proc frequent died` y el script sale con 3.

- [x] **B01 · Retiro de SteamOS Holo y pacman como antes de Holo** (`06101ce`, `77908e7`): sin `[holo-*]`, `pacman-xfer` ni `XferCommand`; `bootstrap.py` idéntico al de `69c84a8` (`IgnorePkg = glibc`, sin `HoldPkg` extra, `SigLevel` de la plantilla: firmas de Arch ARM verificadas). Verificado en instancias nuevas: `pacman.conf` correcto y `pacman -Sy` OK.
- [x] **B02 · Recuadros del instalador al ancho real de la terminal** (`06101ce`…`3759118`). `instalar.sh` (sh de Android) y `primer-arranque.sh` (bash) miden el ancho una vez (`stty size </dev/tty`, `tput`, `COLUMNS`, 60) y de nuevo con SIGWINCH; el texto largo se pliega y las filas de menú se cortan con «…». `primer-arranque.sh` usa bash puro, sin procesos hijos (menús rápidos). Probado a 54 columnas en el Redmi.
- [x] **B03 · Capa y APK regeneradas e instaladas** (varias veces, última `551bb0d`): `armar.sh` (con `$Z` corregido) + `assembleSdk36Debug` + `adb install -r`.
- [x] **B07 · Instalador arreglado tras las pruebas en el teléfono:** `_ancho` ya no aborta con `set -e` cuando falta `tput` (`7594b8d`); `TMPDIR=$P/tmp` para los heredocs de mksh (`1c32edd`); el conteo de columnas UTF-8 usa el `tr` de Android con bytes reales (`3759118`); `stty` ya no se mide dentro de pipes (`e450155`).
- [x] **B08 · `sshd` arranca solo en la sesión** (`551bb0d`, confirmado por el usuario: "ssh ready"): el chequeo de `autostart-android` conectaba a `127.0.0.1:8022`, pero la glibc (0022) mapea la IP virtual de la instancia a `127.0.0.N` y `sshd` escucha ahí; ahora conecta a `/etc/virtual-ip`. `sshd` se lanza con `-e` (errores a su log).
- [x] **B05 · Carpetas de agentes/editor fuera del repo** (`a75ff9a`): `.gitignore` con `.agents/`, `.claude/`, `.codex/`, `.gemini/`, `.mcp.json`, `.vscode/`, `.graphifyignore`, `.codegraph/`, `graphify-out/`, `practica/`, `transcripcion_android_linux.txt`, `__pycache__/`.
- [x] **B06 · `PROYECTO.md` al día** (`a75ff9a`): estado 2026-10-25, filas de pacman e instalador adaptativo, "Próximos pasos" apunta a este archivo. (Archivar sesiones viejas de `NOTAS.md` es opcional y quedó sin hacer.)

- [ ] **B53 · Debian sin los usuarios de sistema de `base-passwd`** (`www-data`, `daemon`, `nobody`...; solo hay `root`, `sshd`, `user`) y sin el paquete `hostname` (`make-ssl-cert` lo necesita). Completar en `bootstrap-debian.py` (p. ej. `update-passwd` o instalar `hostname`) y probar apache2 con workers como `www-data` (fase 4).