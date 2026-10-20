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
7ª sesión: ✅ gestos de 3 dedos (izq/der = escritorios, arriba = fuzzel, abajo = ventanas), ✅ zsh + starship como el PC en kitty.
Cambios hechos en el teléfono por ADB (reversibles): gestos de 3 dedos de HyperOS apagados (`settings put system enable_three_gesture 0`, volver con `1`)
y límite de procesos hijos de Android desactivado (`settings put global settings_enable_monitor_phantom_procs false`, volver con `settings delete ...`).
8ª sesión: ✅ portapapeles Android ↔ Linux en los dos sentidos (`Portapapeles.java`: wl-paste --watch / wl-copy dentro de sway; Android solo deja leer con el escritorio al frente). Cursor: está bien así.
SUPER+V (historial con cliphist) no anda: cliphist es Go y se salta la glibc → llega con la capa seccomp.
9ª sesión: sway no se bloquea en segundo plano; ✅ sin ventana el anfitrión ya no responde frame callbacks (sway con vkcube atrás: 2,7 s de CPU cada 5 s → 0). ✅ ya no se ve estirado en la primera apertura. `vkcube` necesita `--wsi wayland` (parche a Turnip: pendiente menor). El usuario confirmó escala, opacidad, SUPER+A/TAB, scroll, ñ/tildes; falta el clic derecho.
10ª sesión: ✅ **menús/popups GTK funcionan dentro de sway** (probado con gtk3-widget-factory). Las apps GTK se caían al cargar el primer ícono: glycin (gdk-pixbuf) aísla los cargadores con bwrap, que aquí falla → `GLYCIN_DISABLE_SANDBOX=i-know-the-risks` en el entorno de `TerminalService` (aplica al reinstalar la app). Popups en el anfitrión pasan a menor (solo clientes directos, que hoy no se usan).
✅ **Ventanas que no caben se achican en vez de recortarse** (gtk3-widget-factory pide mínimo 1393×740 y la pantalla tiene 432 de ancho lógico): parche propio a wlroots (`0004`, escala de contenido en la escena) y **sway compilado con parche propio** (`sway/parches/0001`, `~/sway/bin/sway`, lo arranca `TerminalService`). Probado: se ve completa, clics y menús caen bien. Los diálogos (fuentes, archivos) ya flotaban solos (el usuario lo confirmó).
**Decidido (11ª sesión):** la ventana *principal* que no cabe **no** pasa sola a flotante: se queda como está (achicada en su tile).
11ª sesión: ✅ **SSH** (`openssh`, servidor en el puerto 8022, sin sudo; se borró `tty:x:5:` de `/etc/group` para que ande el pty). **Steam ARM64 oficial instalado** en `~/.local/share/Steam`: lo primero que lo frena es **SysV IPC** (`semget` = ENOSYS); después pide Xwayland (X11) y gtk2 (no está en Arch ARM, compilar). Detalle en PROYECTO.md, 11ª sesión.
Al cierre de la 11ª: ✅ **SysV IPC emulado** en la glibc (parche 0008, `pruebas/sysv.c`), ✅ relanzar `/proc/self/exe` (0009), ✅ **Xwayland en el sway real** (0010: el seccomp de apps bloquea `setgid` y Xwayland no podía lanzar `xkbcomp`; si el set*id no cambia nada se responde éxito, como el kernel), ✅ certificados HTTPS (`update-ca-trust`), ✅ gtk2 en `/opt/gtk2`, ✅ locales en_US/es_CL, ✅ `sshd` al arrancar sway (puerto 8022). Steam se actualizó solo (438 MB) y ya muestra su ventana X11 (visto en un sway de prueba).
12ª sesión: ✅ **Steam oficial ARM64 abre, inicia sesión y descarga juegos** (biblioteca visible, Undertale bajando). Arreglos: GLX sin override de zink (llvmpipe), glibc **0011** (`get_robust_list` respondida + sockets Unix con ruta larga vía `/proc/self/fd/N`), `-no-cef-sandbox`, **lsof propio** (`steam/lsof.py`, con `pidfd_getfd`: Android no deja leer `/proc/net/tcp`) + `which`. Steam arranca solo con sway.
Ventanas X11 cortadas y borrosas → **Xwayland en píxeles reales**: wlroots **0005** + sway **0002** (`xwayland_scale 2.5` en `sway/config`), Steam con `-forcedesktopscaling 2`. Compilado e instalado; X ya ve 1080×2193. **Falta que el usuario lo pruebe.**
La sesión de Steam **no se guardó** al cerrar la app (Steam guarda el token al salir; la app mata todo de golpe). Detalle y plan en PROYECTO.md, 12ª sesión.
13ª sesión: Steam se ve nítido ✅. ✅ **Undertale (Windows x86) corre con Proton 11 ARM64 + FEX sin contenedor**: pressure-vessel (SteamLinuxRuntime_4-arm64) no puede andar sin root → Proton directo; glibc **0012** (`mprotect` PROT_EXEC con EACCES/execmod → copia anónima, Wine lo necesita); por ahora `PROTON_USE_WINED3D=1` (Turnip sin X11 → DXVK falla). Herramienta `steam/proton-directo` (instalada, elegir "Proton 11 ARM64 (sin contenedor)" en Compatibilidad tras reiniciar Steam). Detalle en PROYECTO.md, 13ª sesión.
14ª sesión: Undertale fluido ✅. ✅ **Lutris** con el Wine de Proton 11 ARM64 (`glibc-prueba/lutris/`: envoltorio con `bin-arm64` en el PATH, esync apagado por el tope de 32768 descriptores, sin runtime, sin DXVK). sway **0003** (flotantes que no caben, ej. diálogo de archivos de GTK, se achican) y **0004** (`scale_to_fit`: juegos X11 de tamaño fijo agrandados por la GPU, regla para `steam_app_*`/`steam_proton`) + escritorio virtual de Wine 640×480 para Undertale en Lutris (Wine reescalaba mal la ventana al girar). Compilado, **sin probar: falta reiniciar sway**. ATLYSS por Steam: necesita "Proton 11 ARM64 (sin contenedor)" en Compatibilidad. Detalle en PROYECTO.md, 14ª sesión.
16ª sesión: ✅ giro y diálogo de archivos (ocultos activados en GTK3), ✅ **Turnip con X11** (`~/turnip-x11`, parches Turnip 0002 KHR_display y 0003 present-wait sin DRI3), ✅ **DXVK** en `proton-directo` y **OpenGL por X11 en la GPU** (Zink, `GALLIUM_DRIVER=zink`), ✅ ATLYSS jugable (13–20 fps; escritorio virtual de Wine 1560×720 en su prefijo; no es límite de GPU), teclado físico arreglado para juegos (sin probar), app reinstalada (cargador igualado). Detalle en PROYECTO.md, 16ª sesión.
17ª sesión: ATLYSS limitado por CPU: todo corría en 2 núcleos (afinidad 6–7 heredada de un hilo de la app) → sway con `taskset -p ff` (reinstalado); núcleos grandes topados a 1,5 GHz por HyperOS; probar `PROTON_LOG=0 FEX_TSOENABLED=0 %command%`. Sin restricciones de batería por ADB (Doze, segundo plano, inicio automático). Detalle en PROYECTO.md, 17ª sesión.
**Siguiente sesión (17ª):** (1) teclado en ATLYSS y kitty; (2) rendimiento: FEX/TSO, perfil; (3) turnip-x11 para todo, Zink GLX en Lutris/Steam; (4) winewayland; (5) audio y mandos; (6) commit de la 16ª.
**Antes (15ª):** (1) tras reiniciar sway, probar Undertale en Lutris (llena la pantalla, giro, toques, nitidez) y el diálogo de archivos; (2) ATLYSS con proton-directo; (3) Turnip con X11 → DXVK; (4) audio y mandos. Lista en PROYECTO.md, "Empezar la próxima sesión por" punto 6.
**Antes (13ª):** (1) preguntar cómo anduvo Undertale; (2) probar `proton-directo` desde Steam (reiniciar Steam con Steam → Exit, elegirlo en Compatibilidad); (3) Turnip con `-Dplatforms=wayland,x11` → DXVK (si falta DRI3: `MESA_VK_WSI_DEBUG=sw`), quitar WineD3D; (4) audio y mandos con Undertale de prueba; (5) commit de 12ª+13ª (aún sin commit). Lista completa en PROYECTO.md, "Empezar la próxima sesión por" punto 6.
**Antes (12ª):** (1) probar Steam con la escala nueva (nítido, entero, menús/toques; ajustar `-forcedesktopscaling`); (2) sesión de Steam: iniciar con "Remember me", ver si guarda el token, si no → cierre ordenado en `TerminalService` (reinstalar app, avisar); mientras, salir con Steam → Exit; (3) gesto/botón para mover ventanas de escritorio (hoy: SUPER + ALT de la fila + número); (4) GL acelerado en X11 (DRI3/glamor); juego nativo arm64. Reinstalar la app cuando convenga para actualizar el cargador (avisar: cierra todo).
**Siguiente: compatibilidad: Go/estáticos (seccomp, arregla también SUPER+V), audio, Xwayland.
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
- [x] Escritorio estilo HyDE, zsh como el PC, gestos de 3 dedos (2026-10-19)
- [x] Portapapeles Android ↔ Linux (2026-10-19, 8ª sesión)
- [x] sway en segundo plano: no se bloquea; frame callbacks sin ventana arreglados (2026-10-19, 9ª sesión)
- [x] menús GTK dentro de sway: funcionan; apps GTK ya no se caen (glycin sin bwrap) (2026-10-19, 10ª sesión)
- [x] sway parchado: ventanas que no caben se achican (wlroots 0004 + sway 0001) (2026-10-19, 10ª sesión)
- [x] ¿ventana principal que no cabe → flotante encima? No: el usuario prefiere dejarlo como está (11ª sesión)
- [x] SysV IPC (0008), Xwayland en sway (0010), Steam ARM64 instalado y actualizado (2026-10-19, 11ª sesión)
- [x] Steam a la vista: abre, inicia sesión, descarga (glibc 0011, lsof propio, sin sandbox CEF) (2026-10-19, 12ª sesión)
- [x] Steam nítido (Xwayland escalado) y Undertale con Proton 11 ARM64 + FEX sin contenedor (glibc 0012, WineD3D) (2026-10-19, 13ª sesión)
- [x] Lutris con el Wine de Proton 11 ARM64; sway 0003 (flotantes que no caben) y 0004 (`scale_to_fit` para juegos) — 0003/0004 sin probar (2026-10-19, 14ª sesión)
- [x] Undertale en Lutris a pantalla completa y escalado (sway 0005 + escritorio virtual de Wine 640×480 en `~/.wine`, F4 dentro) (2026-10-19, 15ª sesión)
- [x] Giro con el juego abierto ✅, diálogo de archivos ✅ (ocultos: `show-hidden` de GTK3 activado) (16ª sesión)
- [x] Turnip con X11 (`~/turnip-x11`, parche 0002 KHR_display) y DXVK en proton-directo (16ª sesión; falta medir ATLYSS)
- [x] ATLYSS por Steam con DXVK: 13–20 fps (antes 10–12), arreglos Turnip 0003 (present wait en X11 sw) y escritorio virtual 1560×720 en su prefijo; teclado físico: letras/espacio/números crudos (mantener W) — reinstalado, sin probar (16ª sesión)
- [ ] **← siguiente (17ª):** probar teclado en ATLYSS y kitty; rendimiento (no es GPU: FEX/TSO, perfil del hilo principal); `~/turnip-x11` para todo + Zink GLX en Lutris/Steam; winewayland (cero copias); audio; mandos. Detalle en PROYECTO.md "Empezar la próxima sesión por" punto 6
- [ ] Viejos: ATLYSS con proton-directo; Turnip con x11 → DXVK; antes: probar Xwayland escalado (wlroots 0005 + sway 0002) con Steam; guardar la sesión de Steam (cierre ordenado); luego Go/estáticos (seccomp), audio; popups en el anfitrión (menor)
- [ ] Mandos (sin `/dev/input`: shim o backend propio). Para jugar, ver PROYECTO.md "Jugar: qué tan posible es" (2026-10-19)
- [ ] Binarios estáticos (ej. `ldconfig`): cargarlos en espacio de usuario desde `execve`

En el teléfono: app sdk36 con `files/archlinux` (Arch + pacman + sway/foot + gcc/meson + Turnip en `~/turnip`, varios GB) y carpetas de pruebas anteriores (`files/arch`, `files/glibc`, `files/glibcp`).
Limpiar pruebas: `adb uninstall dev.ben4shot.glibcprueba.sdk28`, `adb uninstall dev.ben4shot.glibcprueba.sdk36`, `adb shell rm -rf /data/local/tmp/glibc`
