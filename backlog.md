# Backlog

Funciones a agregar, de arriba hacia abajo por prioridad, cada una con sus pasos.
Flujo: elegir la primera → `/story <ID>` (desglosa los pasos en `plan.md`: cómo, pruebas, listo cuando) → `/pair` (TDD, revisión por paso) → commit → borrarla de aquí.
El detalle técnico de los ítems anteriores (B04–B61) está en `git show c2686c1:BACKLOG.md`.

## P0 — Bases: lo que hace funcionar lo demás

Ordenadas por cuánto destraban.

- **B16** · Batería de pruebas de humo que corre en una instancia y dice en un minuto si algo se rompió
  - Shell y paquetes (instalar y quitar uno chico).
  - App gráfica y GPU.
  - Audio y red.
  - Un solo comando que corre todo y resume qué falló.
- **B19** · `/bin`, `/sbin` y `/lib` unificados con `/usr` en Debian, como en un Debian actual
  - Convertir las carpetas en enlaces a `/usr` en instancias nuevas.
  - Migrar las instancias existentes.
  - Comprobar que un paquete que asume el usr unificado se instala.
- **B53** · Usuarios de sistema estándar (`www-data`, `nobody`...) y `hostname` en Debian
  - Agregar los usuarios y grupos de sistema que trae un Debian base.
  - Comprobar que existe el comando `hostname`.
  - Instalar un paquete que crea su propio usuario sin errores.
- **B47** · La raíz de una instancia nueva queda con los permisos correctos desde el inicio
  - Fijar dueño y permisos de `/` y sus carpetas al crear la instancia.
  - Comprobar que `sudo mkdir /x` funciona al abrirla.
- **B31** · Gestor de sesión mínimo para KDE, COSMIC y los bloqueadores
  - Ver qué interfaz piden (logind por D-Bus u otra).
  - Dar la mínima que necesitan.
  - Comprobar KDE y COSMIC.
- **B48** · Pruebas automáticas del supervisor que corren en el PC
  - Arrancar, detener y reiniciar un servicio de prueba.
  - Servicio que falla y servicio con dependencias.
- **B50** · Un servicio que falla al arrancar queda marcado como fallido sin trabar a los demás (depende de B48)
  - Marcar el servicio como fallido con su motivo.
  - Seguir con los demás.
  - Mostrar el estado fallido.
- **B52** · `sshd` lo arranca un solo responsable (depende de B48)
  - Encontrar quién más lo arranca.
  - Dejar uno solo y comprobar que no hay dos copias en el puerto.
- **B25** · Pasar los parches de glibc a la próxima versión de Arch ARM
  - Bajar la nueva glibc y aplicar los parches, arreglando los que no apliquen.
  - Compilar y probar aislada en una instancia.
  - Empaquetar en el APK.
- **B17** · Programas en Go, Rust y los estáticos comunes (`rg`, `fd`, `lazygit`) funcionan
  - Ver por qué fallan hoy (llamadas al sistema directas, sin pasar por la glibc).
  - Arreglar en la capa lo que bloquea.
  - Probar `rg`, `fd` y `lazygit`.
- **B86** · Tabla de red común por subred que leen todas las instancias
  - `RedManager` escribe `files/red/<subred>/hosts` cuando cambia la tabla.
  - El `/etc/hosts` de cada instancia es un enlace a la tabla de su subred (`/data` pasa sin traducir).
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
- **B68** · Elegir entre Debian 12 y Debian 13 al crear una instancia (depende de B19)
  - Base de Debian 13.
  - Opción en el asistente.
  - Paquetes de escritorios para debian-13.
- **B69** · Instancia de Ubuntu 24.04 LTS con el menú de sabores oficiales y Lubuntu (LXQt) probado (depende de B19)
  - Base de Ubuntu 24.04.
  - Menú de sabores (Ubuntu, Kubuntu, Xubuntu, Lubuntu, MATE, Budgie, Unity, Cinnamon).
  - Lubuntu probado.
- **B70** · Elegir entre Ubuntu 24.04 y 26.04 LTS al crear una instancia de Ubuntu (depende de B69)
  - Base de Ubuntu 26.04.
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

- **B10** · Los dos escritorios que quedan en negro o en gris muestran imagen
  - Identificar cuáles son y por qué no dibujan.
  - Arreglarlos.
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
  - Dar los datos que `ss` lee (`/proc/net` está bloqueado en la app).
- **B42** · Llegar a un servicio de la instancia por `127.0.0.1`
  - Que el loopback de la instancia alcance sus propios servicios.
  - Comprobar con un servidor que escucha en la IP de la instancia.
- **B41** · El menú de escritorios del instalador responde al instante
  - Medir dónde se demora.
  - Quitar la espera.

## P3 — Servicios y manejo de instancias

- **B27a** · `sshd` corre como root con separación de privilegios, con la configuración oficial de OpenSSH
- **B27b** · Apache atiende con sus procesos como `www-data` (depende de B53)
- **B51** · Ver el log de `sshd` con `service logs ssh`
- **B44** · La app rechaza nombres de instancia inválidos (vacíos, solo puntos)
- **B28** · Copiar o renombrar una instancia sin que se rompan sus enlaces
  - Encontrar los enlaces y configs que apuntan a `files/archlinux`.
  - Hacerlos relativos o reescribirlos al copiar.
  - Copiar y renombrar desde la app.
- **B22** · Exportar una instancia a un archivo y restaurarla
  - Exportar a un archivo comprimido.
  - Restaurar como instancia nueva.
- **B26b** · Una instancia no ve los archivos de las otras
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

## P4 — Escritorio completo e integración con Android

- **B30** · Batería real del teléfono en la barra del escritorio
- **B32** · Selector de archivos y apertura de enlaces por el portal estándar (xdg-desktop-portal)
- **B33** · Capturar el mouse en juegos y apps 3D (movimiento relativo)
- **B34** · Teclado de Android con autocorrector y predicción en apps Linux
- **B35** · Lápiz con presión e inclinación (Krita, Xournal++)
- **B36** · OpenGL por GPU en X11 sin copias a la CPU
  - Firefox en XFCE X11 hoy dibuja el contenido de la ventana vacío con rayas (los menús salen bien) y avisa `MESA-EGL: DRI3 error`: el servidor no tiene DRI3.
  - Pasar a `AHardwareBuffer` + `ASurfaceTransaction` en el DDX.
  - GLX o DRI3 sobre la GPU.
- **B37** · Cada ventana Linux es una ventana de Android (recientes, pantalla dividida, flotantes)
- **B38** · Cursor de tamaño legible en el teléfono
- **B39** · Notificaciones, abrir enlaces y `/sdcard` en todos los escritorios, no solo en sway
