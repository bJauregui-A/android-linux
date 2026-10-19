# Notas — Redmi 15 5G (spring, HyperOS 3.0 / Android 16)

Bootloader bloqueado, sin root. Todo se hace por ADB (`pm uninstall --user 0`), reversible.

## Debloat (2026-10-18)
- 22 paquetes eliminados → `debloat/eliminados.txt`
- Backup de la lista completa → `debloat/backup-paquetes-2026-10-18.txt`
- Restaurar todo → `debloat/restaurar.sh`
- Restaurar uno → `adb shell cmd package install-existing <paquete>`

## Pendiente de probar
- [ ] Reiniciar el teléfono
- [ ] Abrir un video desde la Galería (se quitó Mi Video; debe usar el reproductor interno o `com.miui.mediaviewer`)
- [ ] Abrir un link desde otra app → debe abrir Edge (se quitó Mi Browser)
- [ ] Revisar que Facebook/Messenger sigan funcionando (se quitaron sus servicios preinstalados)
- [ ] Revisar que no aparezcan errores o notificaciones raras tras el reinicio

## No tocar
`securitycenter`, `powerkeeper`, `joyose`, `xmsf`, `updater`, `gallery`, `mediaviewer`, `longcheertel.cit`, paquetes `qti`/`qualcomm`.
`com.miui.home` se queda instalado aunque se use otro launcher (maneja recientes y gestos).

## Próximos pasos
- Limpiar barra de estado
- Seguir con Mosaico (ver abajo)
- glibc nativa sin root (ver abajo)

## Mosaico (launcher estilo Hyprland) — `mosaico/`
Se abre como app normal (sin categoría HOME): no reemplaza a MIUI Home todavía. MIUI Home nunca se desinstala.
Compilar e instalar: `cd mosaico && ./gradlew assembleDebug && adb install -r app/build/outputs/apk/debug/app-debug.apk`
(MIUI pide aceptar la instalación en el teléfono, o activar "Instalar vía USB" en opciones de desarrollador).

Hecho (v0.1, 2026-10-18):
- Barra tipo waybar (escritorios 1–5, batería, hora), buscador tipo rofi (sin acentos), deslizar para cambiar escritorio
- Escritorio = principal + secundaria (pantalla dividida) + flotante. Tocar un lugar asigna app, mantener lo vacía
- Mantener una app en el buscador: pantalla completa / al lado / flotante

Aprendido probando en el teléfono (sin freeform de desarrollador, sin Shizuku):
- Pantalla dividida: `FLAG_ACTIVITY_LAUNCH_ADJACENT` funciona aunque Mosaico esté a pantalla completa
- Flotante: `setLaunchWindowingMode(5)` (API oculta, vía HiddenApiBypass) usa las ventanas flotantes de HyperOS
- Lo que se abre desde una mitad de la dividida cae en esa mitad: la flotante se abre primero
- Apps `nonResizable` (ej. Brújula) ignoran el flotante y abren a pantalla completa
- Si la app ya estaba abierta, el sistema trae su ventana existente (puede conservar su modo anterior) — por revisar

Pendiente / ideas:
- [ ] Probar en el uso diario antes de agregar la categoría HOME
- [ ] Apps ya abiertas que no cambian de modo al abrir el escritorio
- [ ] Barra flotante sobre las demás apps (overlay) y gestos/atajos (AccessibilityService)
- [ ] Más adelante, si hace falta más control: Shizuku (redimensionar/mover ventanas existentes)

## glibc nativa sin root — `glibc-prueba/` (2026-10-19)
**Contexto completo, decisiones y plan: `glibc-prueba/PROYECTO.md` — empezar por su sección "Para retomar"**
Objetivo principal: que el teléfono sea a la vez Android y un Linux real y modificable — programas de Arch Linux ARM sin recompilar,
nativos (glibc propia en una app, sin root ni proot), con escritorio Wayland mínimo tipo Hyprland adaptado al celular y GPU (Turnip),
sin perder apps bancarias/Play Store y todo reversible.
Estado al cerrar la 2ª sesión (2026-10-19): ✅ pacman, ✅ terminal, ✅ Wayland con sway anidado,
✅ Vulkan con Turnip (vkcube en la Adreno 619). 3ª sesión: ✅ OpenGL 4.6 / GLES 3.2 por GPU (Zink sobre Turnip) en ventanas Wayland; un solo ícono "Arch Linux" que abre sway directo (terminal de rescate: mantener pulsado el ícono).
4ª sesión: ✅ cero copias (AHardwareBuffer + ASurfaceControl + parche a la WSI de Mesa) para clientes directos: CPU de la app de ~50 % a ~11 % de un núcleo.
Probado a mano: cambiar tamaño ✅, salir y volver (sigue en segundo plano) ✅.
5ª sesión: ✅ escritorio por GPU: wlroots parchado (`glibc-prueba/wlroots/`: renderer Vulkan sin DRM, allocator android-ahb-v1, linux-dmabuf v3) → sway compone con Turnip directo en el AHardwareBuffer y sus clientes le pasan dmabufs. vkcube dentro de sway: CPU total ~89 % → ~21 % de un núcleo. El servicio lo usa solo si existe `~/wlroots`.
6ª sesión: medidos sway (19 MB) / swayfx (~60 MB, funciona por GPU) / Hyprland (no arranca: todo supone DRM) → se queda sway.
Escritorio con la config de Hyprland/HyDE del PC llevada a sway (`glibc-prueba/sway/`): atajos, aspecto, waybar, fuzzel, kitty con la config del PC;
app en modo inmersivo (pantalla completa, 1080×2193 px reales); glibc `0007` (`/proc/self/exe` = el programa, kitty lo necesitaba).
7ª sesión: gestos de 3 dedos (sin probar a mano), zsh+starship como el PC, phantom process killer desactivado por ADB (`settings_enable_monitor_phantom_procs false`).
**Siguiente: confirmar gestos; confirmar la opacidad de inactivas; gestos, cursor, portapapeles (pendiente 4 en PROYECTO.md).
Avisar antes de correr scripts que cierran la app (force-stop): el usuario suele estar usándola.**
Root temporal descartado: lo necesario vive en particiones verificadas, y desbloquear/bloquear borra `/data`.

Probado en el teléfono (glibc 2.43, bash 5.3, coreutils 9.12 de Arch ARM):
- Como `shell` (ADB): corre tal cual con `ld-linux-aarch64.so.1 --library-path ...`
- Hijos: binarios con `patchelf --set-interpreter ... --force-rpath --set-rpath ...` (RUNPATH no basta, no es transitivo)
- Dentro de una app: **funciona en targetSdk 36** si el cargador va en `jniLibs` (`libld.so`, `useLegacyPackaging`);
  las bibliotecas y binarios pueden quedar en `files/` (W^X solo bloquea `execve` desde datos, no el mmap del cargador)
- Seccomp de apps bloquea solo 2 syscalls (SIGSYS): `set_robust_list` (99) y `rseq` (293)
  - `rseq`: se apaga con `GLIBC_TUNABLES=glibc.pthread.rseq=0`
  - `set_robust_list`: necesita parche de 1 línea en glibc (o el rastreador ptrace `tracer/`, que la convierte en ENOSYS)
- Funciona: fork/exec, pipes, hilos (`sort --parallel`), stat, cp, mktemp, date, sleep, timeout/señales
- Android no deja crear enlaces duros → el instalador debe convertirlos en copias
- Falta `/etc/passwd` etc. → traducción de rutas

Siguiente:
- [x] glibc 2.43 propia sin `set_robust_list`/`rseq` (2026-10-19): `glibc-prueba/glibc/compilar.sh` (Docker, no instala nada en el PC).
      Probada en la app sdk36 **sin rastreador ni GLIBC_TUNABLES**: bash, fork/exec, pipes, hilos, señales ✅
- [x] Traducción de rutas (`/usr`, `/etc`... → prefijo, con `GLIBC_PREFIX`) y `execve` vía el cargador, scripts `#!` incluidos (2026-10-19).
      `ls /`, `id`, `PATH`, `cd`/`pwd`, symlinks, `env -i`, binarios de Android: todo ✅ sin `patchelf` ni `--library-path`
- [x] Gestor de paquetes: **pacman real de Arch ARM dentro de la app** (2026-10-19). `glibc-prueba/scripts/instalar-arch.sh`,
      luego `GLIBC_FAKEROOT=1 pacman -S ...`. Firmas verificadas. Probado con nano, htop, git (+perl)
      La glibc atrapa SIGSYS → ENOSYS (`GLIBC_DEBUG_SIGSYS=1` las muestra); binarios estáticos aún no corren
- [x] Terminal dentro de la app (vista de Termux + pty; parches glibc 0004 termios, 0005 SIGSYS protegido, 0006 /proc sintético) (2026-10-19)
- [x] DNS de Android → `/etc/resolv.conf` (lo escribe la terminal al abrir)
- [x] Compositor Wayland propio en la app (`app/src/main/cpp/anfitrion.c`) + sway anidado; tacto/scroll/teclado latam (2026-10-19)
- [x] Turnip (Adreno 619, KGSL) compilado dentro del teléfono; vkcube ✅ (2026-10-19)
- [x] Zink (OpenGL sobre Turnip) con el mesa de Arch, sin recompilar; `turnip/egl-zink.c` (LD_PRELOAD) para que EGL use kopper por wl_shm (2026-10-19)
- [x] Keymap xkb real (latam) para clientes conectados directo al anfitrión (2026-10-19)
- [x] dmabuf: el anfitrión implementa linux-dmabuf; Turnip compilado con `kgsl,msm` (si no, sin dmabuf en la WSI). El cliente ya no copia; el anfitrión aún lee por CPU (2026-10-19)
- [x] Cero copias: protocolo propio `android-ahb-v1` (el anfitrión reserva AHardwareBuffer y da su dmabuf), capa ASurfaceControl, fences implícitas, frame callbacks con AChoreographer; parche `turnip/parches/0001` a la WSI de Mesa (vkcube y GL por Zink lo usan solos) (2026-10-19)
- [x] Escritorio por GPU: wlroots 0.20.2 parchado (`wlroots/parches/0001`–`0003`), sway con renderer Vulkan + buffers del anfitrión + linux-dmabuf para sus clientes (2026-10-19)
- [ ] **← siguiente:** escritorio cómodo (gestos, lanzador, popups, portapapeles); luego Xwayland, Steam
- [ ] Binarios estáticos (ej. `ldconfig`): cargarlos en espacio de usuario desde `execve`

En el teléfono: app sdk36 con `files/archlinux` (Arch + pacman + sway/foot + gcc/meson + Turnip en `~/turnip`, varios GB) y carpetas de pruebas anteriores (`files/arch`, `files/glibc`, `files/glibcp`).
Limpiar pruebas: `adb uninstall dev.ben4shot.glibcprueba.sdk28`, `adb uninstall dev.ben4shot.glibcprueba.sdk36`, `adb shell rm -rf /data/local/tmp/glibc`
