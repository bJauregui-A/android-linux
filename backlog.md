# Backlog

Funciones a agregar, de arriba hacia abajo por prioridad, cada una con sus pasos.
Flujo: elegir la primera → `/story <ID>` (desglosa los pasos en `plan.md`: cómo, pruebas, listo cuando) → `/pair` (TDD, revisión por paso) → commit → borrarla de aquí.
Lo de cada distro se arregla al crear la instancia, en el módulo de esa distro; las instancias viejas se recrean o se migran aparte.
El detalle técnico de los ítems anteriores (B04–B61) está en `git show c2686c1:BACKLOG.md`.

## P0 — Bases: lo que hace funcionar lo demás

Ordenadas por cuánto destraban.

- **B96** · Los permisos se aplican según el usuario virtual: dueño, grupo y otros
  - Hoy cuentan solo los bits del dueño, para todos: `user` crea en `/` sin `sudo` y `www-data` lee un `600` de `user`.
  - Decidir el acceso con el dueño virtual (0026, 0027), el modo y las credenciales del proceso (uid, gid y grupos extra) al abrir, crear, borrar, renombrar, ejecutar, entrar a carpetas y en `access`.
  - El bit sticky de `/tmp`: solo el dueño borra lo suyo.
  - Comprobar con `user`, `www-data` y root sobre `600`, `640`, `644`, `755` y `1777`.
- **B92** · Los enlaces simbólicos absolutos se guardan como en Linux, sin la ruta real de Android
  - Hoy `symlinkat` guarda `/data/user/0/<app>/files/instancias/<id>/usr/...` y `readlinkat` le quita el prefijo al leer: si la instancia cambia de carpeta, se rompen (ya hay 4 rotos en `dev-6918`).
  - Que el enlace guarde el destino de Linux y se resuelva con el prefijo de la instancia donde está guardado.
  - Reparar los enlaces de las instancias que ya existen.
- **B89** · `chroot` a una carpeta dentro de la instancia, como en una máquina real (depende de B92)
  - Hoy adentro `chroot` solo acepta `/` (0003); a otra carpeta llega al kernel y falla. Lo necesitan `sshd` con separación de privilegios (B27a), vsftpd y postfix.
  - Que `chroot` (y `pivot_root`) cambie la raíz del proceso y de sus hijos a esa carpeta.
  - Comprobar con `chroot /x /bin/sh` y `arch-chroot` sobre una raíz armada dentro de la instancia.
- **B31** · Gestor de sesión mínimo para KDE, COSMIC y los bloqueadores
  - Medir en sus logs qué piden de `org.freedesktop.login1` antes de inventar respuestas.
  - Dar la mínima interfaz que necesitan (sesión activa, `Inhibit`, `CanSuspend` = no).
  - Comprobar KDE y COSMIC.
- **B48** · Pruebas automáticas del supervisor que corren en el PC
  - La prueba con `SERVICE_ROOT` (raíz falsa) se hizo a mano y no quedó guardada: dejarla en `pruebas/supervisor/`.
  - Arrancar, detener y reiniciar un servicio de prueba; alias, `enable`/`disable`, `logs`, nombre inexistente.
  - Servicio que falla y servicio con dependencias.
- **B50** · Un servicio que muere al arrancar no traba al supervisor (depende de B48)
  - Hoy el supervisor reinicia en su propio hilo con `usleep(500000)` (`supervisor/proceso.c`): un servicio que muere al instante lo deja reiniciando sin parar y a los clientes esperando.
  - Reintentar con espera que no bloquee y con un límite.
  - Marcarlo como fallido con su motivo y mostrarlo en el estado.
- **B52** · `sshd` lo arranca un solo responsable (depende de B48)
  - Hoy lo arrancan `autostart-android` (si no está habilitado) y el supervisor (si lo está).
  - Que `autostart-android` lo pida siempre al supervisor.
  - Comprobar que no hay dos copias en el puerto.
- **B86** · Tabla de red común por subred que leen todas las instancias
  - `RedManager` escribe la tabla de cada subred cuando cambia.
  - El `/etc/hosts` de cada instancia muestra la tabla de su subred (sin depender de que `/data` pase sin traducir: B26b lo cierra).
  - Gateway calculado del CIDR, no `10.0.0.1` fijo.
  - Nombre de equipo propio con `nss-myhostname` (comprobar que está en Arch y Debian) o un parche de glibc si no.

## P1 — Escritorios por distribución

Cada distro ofrece la lista de su instalador oficial (archinstall, tasksel, sabores de Ubuntu). Lo no probado se muestra como experimental.

- **B65** · Menú de Arch con los escritorios de archinstall
  - Orden y lista como archinstall.
  - Marcar como experimentales los no probados.
- **B64** · Mostrar junto a cada escritorio del menú si usa Wayland o X11
  - Leer el protocolo de cada escritorio.
  - Mostrarlo en el menú.
- **B68** · Elegir entre Debian 12 y Debian 13 al crear una instancia
  - Base de Debian 13 (trixie).
  - Opción en el asistente.
  - Paquetes de escritorios para debian-13.
- **B69** · Instancia de Ubuntu 24.04 LTS con el menú de sabores oficiales y Lubuntu (LXQt) probado
  - Base de Ubuntu 24.04 arm64, con su comprobación del `/usr` unificado.
  - Menú de sabores (Ubuntu, Kubuntu, Xubuntu, Lubuntu, MATE, Budgie, Unity, Cinnamon).
  - Lubuntu probado.
- **B70** · Elegir entre Ubuntu 24.04 y 26.04 LTS al crear una instancia de Ubuntu (depende de B69)
  - Imagen oficial `ubuntu-base-26.04-arm64`.
  - Opción en el asistente y paquetes por versión.

Escritorios del instalador oficial que todavía no tenemos. Cada uno deja de ser experimental cuando se prueba. Pasos de cada uno: declarar sus paquetes por distro y versión, crear su sesión, probarlo y anotarlo en `PROBADO_EN`.
- **B73** · GNOME
- **B74** · GNOME Flashback (Debian)
- **B75** · Cinnamon
- **B76** · MATE
- **B77** · Budgie
- **B78** · LXDE (Debian)
- **B79** · Unity (Ubuntu)
- **B80** · i3 (Arch)
- **B81** · bspwm (Arch)
- **B82** · awesome (Arch)
- **B83** · Enlightenment (Arch)
- **B84** · Deepin (Arch)

## P2 — Validar lo que ya existe

- **B14** · Al cerrar la sesión los programas terminan en orden, sin huérfanos
  - Mandar la señal de cierre y esperar antes de matar.
  - Cerrar `dbus-daemon`, `xfconfd`, `ssh-agent` y los demás que hoy quedan huérfanos.
- **B15** · Desbloquear Phosh y COSMIC con la contraseña
  - Ver cómo verifican la contraseña (PAM).
  - Hacer que funcione en la instancia.
- **B13** · Instalar herramientas de compilación en Debian y compilar un programa dentro de la instancia
  - Instalar `build-essential`.
  - Compilar y correr un programa de prueba.
- **B40** · `ss` lista las conexiones de la instancia
  - Hoy da `Cannot open netlink socket`: la capa emula solo el Netlink de rutas (0020, 0021), no `SOCK_DIAG`.
  - Dar lo que `ss` lee, sin `/proc/net` (bloqueado en la app).
- **B42** · Un servicio de la instancia responde en `127.0.0.1`, como en una máquina real
  - Hoy escucha en el `127.0.0.N` de la instancia (red virtual, 0022), y `127.0.0.1` no llega.
  - Que el `127.0.0.1` de la instancia alcance sus propios servicios.
  - Comprobar con un servidor que escucha en `0.0.0.0`.
- **B41** · El menú de escritorios del instalador responde al instante
  - Hoy `primer-arranque.sh` lee cada `escritorio.conf` en un subproceso por fila y por redibujo.
  - Leerlos una sola vez al abrir el menú.

## P3 — Servicios y manejo de instancias

- **B27a** · `sshd` corre como root con separación de privilegios, con la configuración oficial de OpenSSH (depende de B89)
- **B27b** · Apache atiende con sus procesos como `www-data` (depende de B96)
- **B97** · Capacidades y límites de root virtuales
  - `capset`, `capget`, `PR_SET_KEEPCAPS` y `PR_CAPBSET_*` virtuales (hoy `setpriv --reuid` exige bajar primero el gid).
  - `setrlimit` respeta el tope duro que recuerda el proceso.
  - `mount`, `unshare` y `setns` de un usuario que no es root dan `EPERM`, como en Linux (los de root son B90).
- **B98** · Detalles de setuid y setgid como en Linux
  - `no_new_privs` impide que `execve` de un setuid cambie el usuario.
  - `chown` limpia los bits setuid y setgid.
  - Una carpeta con setgid hace que lo creado dentro herede su grupo.
- **B51** · Ver el log de `sshd` con `service logs ssh`
  - Hoy `sshd -D -e` deja sus errores en `/dev/null` y el log solo tiene las líneas `INICIO`.
  - Que sus mensajes lleguen al log del supervisor.
- **B44** · La app rechaza nombres de instancia inválidos
  - Hoy el nombre `.` genera el id `--67263`, que empieza con guiones y rompe `ls` y los scripts.
  - Rechazar nombres vacíos o de solo puntos y que el id nunca empiece con guion.
- **B28** · Copiar o renombrar una instancia sin que se rompa nada (depende de B92)
  - Encontrar las configs que guardan la ruta real de la instancia.
  - Copiar y renombrar desde la app.
- **B22** · Exportar una instancia a un archivo y restaurarla (depende de B92)
  - Exportar a un archivo comprimido.
  - Restaurar como instancia nueva.
- **B26b** · Una instancia no ve los archivos de Android ni los de las otras instancias
  - Hoy `/data`, `/system`, `/vendor` y otras pasan sin traducir: desde una instancia se lee `/data/user/0/<app>/files/instancias/<otra>`.
  - Dejar visible solo lo que la instancia necesita para correr (el cargador de la app, `/proc`, `/dev`, `/sys`) y la tabla de red (B86).
  - `/sdcard` cerrado por defecto; se abre solo en las instancias donde el usuario lo activa desde la app.
  - Comprobar que desde una instancia no se lista ni se lee otra instancia ni `/data`, ni `/sdcard` si no está activado.
- **B26c** · Una instancia solo ve y señala sus propios procesos (`ps`, `pgrep`, `htop`, `kill`)
  - Todas corren con el mismo usuario de Android y ven el `/proc` real; el kernel no tiene namespaces de usuario (`unshare -U` → `EINVAL`), así que el filtro va en nuestra glibc: es contra errores (como `pgrep -x pipewire` de otra instancia), no una barrera de seguridad.
  - Al listar `/proc`, mostrar solo los procesos de la instancia (por su ruta en cmdline o cwd, el criterio de `Pausa`), más `self` y lo que no es un pid.
  - Rechazar `kill` a procesos de otra instancia.
  - La pausa y el cierre alcanzan a los procesos no volcables. Con `/proc` en `hidepid=invisible`, un proceso que hace `PR_SET_DUMPABLE 0` (`ssh-agent`, `gpg-agent`) desaparece para la app. La marca se respeta: en ese momento, nuestra glibc le manda a la app un `pidfd` del proceso por un socket, y la app lo guarda en memoria por instancia. No va en un archivo, porque todo corre con el mismo usuario y cualquier proceso podría leerlo. Al pausar o cerrar, la app señala por `pidfd`, que no se confunde aunque el pid se reutilice. Lo primero es comprobar que el seccomp de la app permite `pidfd_open` y `pidfd_send_signal`.
  - Resolver el `sshd` compartido del puerto 8022 (hoy lo arranca la primera instancia y las demás no lo ven).
- **B63** · Regenerar desde una instancia lo compilado en el teléfono (Mesa, wlroots, sway, mesa-gl) para rearmar el APK sin `trabajo/compilados.tar`
- **B24a** · Colas de mensajes SysV
- **B24b** · La memoria compartida no ocupa disco ni deja basura al cerrarse los programas
- **B20** · Crear una instancia a partir de un Dockerfile
  - Leer `FROM`, `RUN`, `COPY` y `ENV`.
  - Aplicarlos sobre una instancia nueva.
- **B25** · Pasar los parches de glibc a la próxima versión, cuando Arch ARM la publique
  - Hoy Arch ARM y nosotros estamos en glibc 2.43: no hay nada que pasar.
  - Bajar la nueva glibc y aplicar los parches, arreglando los que no apliquen.
  - Compilar y probar aislada en una instancia.
  - Empaquetar en el APK.

## P4 — Escritorio completo e integración con Android

- **B30** · Batería real del teléfono en la barra del escritorio
- **B32** · Selector de archivos y apertura de enlaces por el portal estándar (xdg-desktop-portal)
- **B33** · Capturar el mouse en juegos y apps 3D (movimiento relativo)
- **B34** · Teclado de Android con autocorrector y predicción en apps Linux
- **B35** · Lápiz con presión e inclinación (Krita, Xournal++)
- **B87** · Juegos y videos a pantalla completa en XFCE X11 sin copia, con el compositor de xfwm4 encendido
  - Hoy xfwm4 deja redirigida una ventana administrada a pantalla completa (aunque tenga `unredirect_overlays` o `_NET_WM_BYPASS_COMPOSITOR`) y Present la entrega por copia; sin compositor va por flip (B36).
  - Averiguar qué le falta a xfwm4 para sacarla del compositor y arreglarlo (ajuste o parche).
- **B88** · OpenGL y Vulkan por GPU sin copias a la CPU en Xwayland (sway y los demás escritorios Wayland)
  - Hoy Xwayland no tiene DRI3 (sin dispositivo DRM no hay glamor): GL va por drisw y Vulkan por el camino sw del WSI, y cada cuadro se copia a la CPU. En X11 directo ya no (B36).
  - Darle a Xwayland DRI3 con buffers AHardwareBuffer, sobre `android_ahb_v1`, o llevar las apps X11 de esos escritorios al servidor X de la app.
- **B37** · Cada ventana Linux es una ventana de Android (recientes, pantalla dividida, flotantes)
- **B38** · Cursor de tamaño legible en el teléfono
- **B39** · Notificaciones, abrir enlaces y `/sdcard` (en las instancias que lo tienen activado) en todos los escritorios, no solo en sway (depende de B26b)

## Quizás — Solo si se corren los instaladores reales de cada distro

- **B90** · Las llamadas de una máquina real que no existen en la app se omiten o se adaptan, sin error
  - `mount` y `umount` de `/proc`, `/sys`, `/dev`, `/run`, `tmpfs` y montajes de carpeta responden como hechos.
  - Cargar módulos del kernel, swap y montar discos se omiten.
  - Apagar y reiniciar cierran o reinician la instancia.
  - Instalar el kernel, el initramfs y el gestor de arranque (`mkinitcpio`, `update-initramfs`, `grub-install`, `bootctl`, `efibootmgr`) termina bien sin hacer nada, para los paquetes que los disparan.
  - Particionar y formatear (`sfdisk`, `parted`, `mkfs.*`) responden sin tocar nada.
