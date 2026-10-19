# Linux real en Android, sin root

Documento de contexto del proyecto. Resume la idea, las decisiones tomadas (y por qué), lo que ya se probó en el teléfono y lo que sigue. Escrito el 2026-10-19 (primera sesión) y actualizado al cerrar la segunda (terminal, Wayland, GPU).

## Objetivo principal

Que el teléfono (Redmi 15 5G, HyperOS, **sin root**) sea a la vez Android y un **Linux real y totalmente modificable**: programas de Arch Linux ARM sin recompilar corriendo nativos (glibc propia dentro de una app normal, sin proot ni emulación), con un **escritorio Wayland mínimo y modificable, tipo Hyprland adaptado al celular**, y **aceleración por GPU** (Turnip en la Adreno 619). Sin perder lo de Android que importa (apps bancarias chilenas, Play Store, cámara, pagos) y todo reversible: es una app, se desinstala y el teléfono queda igual. Más adelante: integrarlo con Mosaico (cada ventana Linux como ventana Android) y, si se puede, Steam.

## Para retomar (estado al 2026-10-19, octava sesión)

| Frente | Estado |
|---|---|
| glibc propia + pacman de Arch ARM | ✅ (parches `0001`–`0007`) |
| App única "Arch Linux" | ✅ abre el escritorio y arranca sway sola; terminal de rescate en el atajo del ícono |
| Terminal | ✅ bash interactivo, htop, nano, `sudo pacman` (foot dentro de sway, o la de rescate) |
| Wayland | ✅ anfitrión propio + sway 1.12 anidado + foot; tacto, scroll, teclado latam; keymap xkb para clientes directos |
| GPU | ✅ Vulkan: Turnip (KGSL) compilado en el teléfono. ✅ OpenGL 4.6 / GLES 3.2: Zink sobre Turnip. ✅ **Cero copias** para clientes directos: `AHardwareBuffer` + `ASurfaceControl` (protocolo propio `android-ahb-v1` + parche a la WSI de Mesa) |
| Escritorio | ✅ sway con los atajos y el aspecto de la config de Hyprland/HyDE del PC (`sway/`), waybar, fuzzel, kitty con la config del PC, modo inmersivo a pantalla completa (1080×2193 px reales). swayfx también funciona por GPU (`~/swayfx`, no es el por defecto); Hyprland instalado pero no arranca (ver "sway, swayfx y Hyprland") |
| Escritorio por GPU | ✅ sway compone con el renderer **Vulkan** de wlroots (parchado, `wlroots/`) directo en AHardwareBuffers del anfitrión; sus clientes le pasan dmabufs. vkcube dentro de sway: CPU total 8,9 s → 2,1 s cada 10 s |

**8ª sesión (2026-10-19), cerrada: ✅ portapapeles Android ↔ Linux, probado por el usuario en los dos sentidos.** El cursor está bien así (no tocar).
- **Por qué no en el anfitrión**: el backend wayland de wlroots no reenvía el portapapeles al compositor padre (no usa `wl_data_device`), así que un `wl_data_device_manager` en `anfitrion.c` no le serviría a sway. El puente va **dentro de sway** con wl-clipboard (protocolo data-control, sin foco): `Portapapeles.java`.
- **Linux → Android**: `TerminalService.iniciarSway()` llama a `Portapapeles.iniciar()`, que corre `wl-paste --type text --watch sh -c 'base64 -w0; echo'` en `wayland-1` (el socket de sway anidado): una línea base64 por cambio → `setPrimaryClip` (escribir sí se puede en segundo plano). Si wl-paste se cae (ej. el socket de sway aún no existe al arrancar) reintenta cada 2 s mientras sway viva.
- **Android → Linux**: Android solo deja **leer** el portapapeles a la app enfocada → `WaylandActivity.onWindowFocusChanged` llama a `Portapapeles.foco()`: al ganar el foco lee el portapapeles y registra un `OnPrimaryClipChangedListener` (lo quita al perderlo) → `wl-copy -- <texto>`. **Por stdin desde Java llegaba vacío** (a mano por stdin sí funciona; causa no encontrada), por eso va como argumento; > 100 KB va por stdin (MAX_ARG_STRLEN). Errores de wl-copy en `/tmp/wl-copy.log`. `ultimo` evita rebotes entre los dos lados. Solo texto (imágenes: pendiente).
- `TerminalService.linux(args...)`: ProcessBuilder de un programa Linux conectado a sway, con el entorno con que arrancó sway (`entornoSway`, para no reescribir `resolv.conf` en cada copia).
- **SUPER+V (historial) no funciona y nunca funcionó**: `cliphist` es Go → syscalls directas sin la traducción de rutas de la glibc ("opening db: create cache dir: mkdir /home: read-only file system" en `sway.log`). Lo que se ve al abrirlo es el buscador de fuzzel con la lista vacía. Se arregla con la capa seccomp de "Compatibilidad completa" 1 (o, de parche, un historial propio en bash/python).
- **Visto por ADB, sin confirmar**: con la app en segundo plano, `wl-paste`/`swaymsg` lanzados por `run-as` no recibían respuesta de sway (en primer plano sí). Revisar si sway se bloquea sin ventana del anfitrión (relacionado con "frame callbacks sin ventana", pendiente menor).
- **Probar programas dentro de sway por ADB sin cerrar nada**: `scripts/wl.sh` (uso en su cabecera): `GLIBC_PREFIX=/data/data/<paquete>/files/archlinux GLIBC_LOADER=$N/libldp.so HOME=/home/user PATH=/usr/bin XDG_RUNTIME_DIR=/run/user/$(id -u) WAYLAND_DISPLAY=wayland-1 /system/bin/timeout 5 $N/libldp.so <programa>`, donde `$N` = `legacyNativeLibraryDir` de `dumpsys package` + `/arm64` (**cambia con cada `adb install`**; `run-as` no puede listar `/data/app`). Correr con `adb shell "run-as <paquete> env WL_LIB=$N sh /data/local/tmp/wl.sh ..."`. LD_PRELOAD no se puede poner afuera (rompe el `sh` de Android): pasarlo con `/usr/bin/env` de Arch.
- Privacidad: `screencap` con la app en segundo plano captura lo que el usuario tenga abierto (pasó con un chat) → capturar solo cuando el escritorio esté al frente.
- Hay ~60 `sway-ipc.*.sock` viejos en `run/user/<uid>/` (uno por cada arranque de sway): limpiar alguna vez.

**7ª sesión (2026-10-19), cerrada:** el usuario probó: atajos ✅, girar ✅, **gestos de 3 dedos ✅**, kitty con zsh ✅ (portapapeles SUPER+V sin probar).
- **Gestos**: el anfitrión ofrece `zwp_pointer_gestures_v1` v3 (solo manda swipe; pinch/hold se crean vacíos) y `WaylandActivity` pasa a "deslizar" con 3+ dedos (`Wayland.gesto`: fase 0 empieza, 1 avanza, 2 termina, 3 cancelado; al poner/levantar un dedo el siguiente MOVE solo recentra, también para el scroll de 2 dedos). sway: `bindgesture swipe:left/right` = escritorio siguiente/anterior, `up` = fuzzel, `down` = selector de ventanas (sin número de dedos: vale para 3 o 4). wlroots (backend wayland) ya los reenvía sin parche.
- **HyperOS se quedaba con los toques de 3 dedos** (`enable_three_gesture=1`: abajo = captura, lados = pantalla dividida, mantener = captura parcial; la app recibía ACTION_CANCEL). Apagados por elección del usuario: `adb shell settings put system enable_three_gesture 0` (deshacer: `1`). Ajuste privado de HyperOS: una app no puede cambiarlo sola. La captura sigue con encendido + bajar volumen.
- **zsh como en el PC** (los colores "de kitty" eran de zsh + starship de HyDE; kitty.conf ya era idéntica): `sway/zsh/.zshrc` (sin oh-my-zsh: starship con el `starship.toml` del PC, zsh-autosuggestions, zsh-syntax-highlighting, ESC ESC = sudo, eza si está) y `sway/zsh/starship.toml`; `subir-sway.sh` los copia, `test-sway-config.sh` instala `zsh starship zsh-autosuggestions zsh-syntax-highlighting fastfetch eza`. `TerminalService` exporta `SHELL=/usr/bin/zsh` si existe (kitty/foot la abren; la terminal de rescate y el arranque de sway siguen con `bash -l`). fastfetch: con < 80 columnas, logo arriba y datos cortos (el logo sale grande igual: `--logo arch_small` no lo toma en el teléfono, sin investigar); muestra Shell/WM = `libldp.so` porque el parche 0007 solo arregla `/proc/self/exe`, no `/proc/<otro pid>/exe`.
- **Phantom process killer** (Android 12+ mata procesos hijos pasado un total de 32 entre todas las apps, y a los que gastan CPU en segundo plano): estaba activo y la app tiene ~14 procesos en reposo → desactivado con `adb shell settings put global settings_enable_monitor_phantom_procs false` (persiste tras reiniciar; deshacer: `settings delete global settings_enable_monitor_phantom_procs`).
- Probar teclas por ADB sin cerrar nada: tocar SUPER de la fila (`adb shell input tap 594 2246`, vertical) y luego `adb shell input keyevent KEYCODE_T`; `input keycombination` no llega. ADB no simula multitáctil.

**Empezar la próxima sesión por** (en orden; el usuario eligió escritorio cómodo primero y luego compatibilidad):
1. **Ojo: el usuario suele estar usando el teléfono.** `scripts/correr.sh`, `correr-wl.sh` y `adb install -r` cierran sway y todo lo abierto: avisar antes. Para mirar sin cerrar nada: `adb exec-out screencap -p` y `adb shell "run-as dev.ben4shot.glibcprueba.sdk36 cat files/archlinux/tmp/sway.log"`.
2. ~~Cursor más grande~~: el usuario dice que está bien. ~~Portapapeles Android ↔ Linux~~ ✅ (8ª sesión).
3. **¿sway se bloquea con la app en segundo plano?** (ver 8ª sesión): confirmar con la app al frente vs. atrás; si es así, que el anfitrión siga atendiendo sin ventana.
4. **Popups xdg y `wl_subcompositor`** en el anfitrión (solo clientes directos, sin sway en medio).
5. Preguntar por la **escala** (`output * scale 2.5`; buffers ya nativos 1080 px) y confirmar la **opacidad de inactivas** (`opacidad.py`: probar `swaymsg '[app_id=kitty] opacity 0.3'` + captura).
6. Luego lo grande de "Compatibilidad completa" (abajo): capa seccomp para Go/estáticos, audio, Xwayland.
7. Menores: frame callbacks sin ventana se responden al tiro (batería en segundo plano); si vuelve a pedir Hyprland, ver "sway, swayfx y Hyprland".

**Cómo se usa hoy:**
1. Un solo ícono, **"Arch Linux"** (`WaylandActivity`, pantalla completa: las barras de Android se asoman deslizando desde el borde): abre el escritorio y el servicio en primer plano (`TerminalService`) arranca sway solo si no está corriendo (log en `/tmp/sway.log`; el servicio vive mientras haya sway o bash). SUPER y luego T (o Enter) → kitty; SUPER+ALT+T → foot (heredan todo el entorno: Wayland, Turnip, Zink, D-Bus). SUPER+/ muestra todos los atajos (son los de HyDE, ver "Escritorio estilo HyDE"). Cambiar la config: editar `sway/` en el repo, `scripts/subir-sway.sh`, y SUPER+SHIFT+C (recargar) o reabrir la app.
2. Terminal de rescate (si sway no arranca): mantener pulsado el ícono → "Terminal" (`TerminalActivity`, tarea aparte). Paquetes: `sudo pacman -S <paquete>` (`sudo` = modo fakeroot de la glibc). **No correr `sway` a mano**: ya corre (dos sways se pelean la pantalla). En el escritorio, fila de abajo: ⌨ (teclado Android), ESC, TAB, CTRL/ALT/SUPER (valen para la tecla siguiente), flechas.
3. Vulkan: desde una foot de sway, `vkcube` (la terminal exporta `VK_ICD_FILENAMES`). Si existe `~/wlroots/lib/libwlroots-0.20.so`, el servicio arranca sway con `WLR_RENDERER=vulkan` y `LD_LIBRARY_PATH=/home/user/wlroots/lib` (escritorio por GPU); si no, `WLR_RENDERER=pixman` y `MESA_VK_WSI_DEBUG=sw` como antes.
4. OpenGL: `es2gears_wayland`, `eglinfo -B -p wayland` (la terminal exporta `MESA_LOADER_DRIVER_OVERRIDE=zink` y `LD_PRELOAD=~/turnip/lib/libegl-zink.so`).

**Probar a mano (no se pudo por ADB):** SUPER+V (portapapeles), SUPER+A (fuzzel), SUPER+TAB, que las barras de Android aparezcan al deslizar y se escondan solas, kitty (pestañas, letra, padding de 25 en pantalla chica), que waybar no choque con la cámara, opacidad de inactivas. sway por GPU: abrir/cerrar el teclado, girar, salir y volver; teclado físico (US) en el escritorio, scroll con dos dedos, clic derecho (mantener), ñ/tildes desde Gboard, nano/htop a pantalla completa, girar la pantalla.

**Pendientes, en el orden sugerido:**
1. ~~Zink~~ ✅ (ver "GPU").
2. ~~Evitar la copia por CPU~~ ✅ **cero copias** (2026-10-19, ver "GPU → Cero copias"): vkcube/es2gears directos al anfitrión pasan de ~50 % a ~11 % de un núcleo para todo el proceso de la app. Falta para los clientes dentro de sway (pendiente 3).
3. ~~Escritorio por GPU~~ ✅ (2026-10-19, ver "Escritorio por GPU"). Hyprland: usa aquamarine (no wlroots) → habría que repetir los parches allí.
4. **Escritorio cómodo en el celular**: ✅ gestos de 3 dedos (7ª sesión, probados), ✅ zsh/starship como el PC. ✅ config de sway con atajos y aspecto de HyDE, waybar, fuzzel, kitty, modo inmersivo (ver "Escritorio estilo HyDE"). Falta: confirmar que la opacidad de inactivas (0.75) se aplica; cursor más grande; popups xdg (hoy se cierran: menús GTK/Qt no andan); ~~portapapeles Android ↔ Wayland~~ ✅ (8ª sesión, `Portapapeles.java`); historial SUPER+V (cliphist es Go: espera la capa seccomp); `wl_subcompositor` (libdecor lo pide para decoraciones). Keymap para clientes directos: ✅ (latam, `keymap.h`).
5. **Xwayland** (apps X11; Steam lo necesita).
6. **Steam**: revisar el cliente oficial para ARM que menciona el usuario; si no sirve, FEX-Emu (ver abajo).
7. Binarios estáticos (cargarlos en espacio de usuario desde `execve`).
8. Integración con Mosaico: cada ventana Linux = ventana Android (recientes, dividida, flotante). El usuario anotó que más adelante se puede saltar el `SurfaceView`.
9. Menores: `/dev/shm` es carpeta en disco (¿memfd?); re-ejecutar `instalar-arch.sh` desde cero para validar el bootstrap con todos los arreglos.

### Compatibilidad completa (lista de la 7ª sesión, de más a menos impacto)
1. Programas que no pasan por la glibc (Go, estáticos, `syscall()` directo): filtro seccomp propio (`SECCOMP_RET_TRAP` para syscalls con rutas cuyo `instruction_pointer` está fuera de libc) → el manejador de SIGSYS de la glibc traduce; estáticos cargados en espacio de usuario desde `execve`.
2. Audio: PipeWire/PulseAudio con salida a pipe → AAudio en la app (luego micrófono).
3. Xwayland (sin glamor/DRM: `-shm`), MIT-SHM necesita SysV IPC.
4. ~~Phantom process killer~~ ✅ desactivado.
5. Integración: notificaciones (D-Bus → Android), `xdg-open` → intents, `/sdcard`.
6. SysV IPC emulado (memfd + registro), mutex robustos compartidos, `/dev/shm` en memfd.
7. Teclado de Android de verdad: `text-input-v3` ↔ `InputConnection` (autocorrector, predicción).
8. Hardware sintético: batería (`BatteryManager`), red (`getifaddrs`/netlink), sensores.
9. Mantener la glibc al día (rebase de los parches con cada glibc de Arch ARM).
10. x86 (Steam) con FEX. 11. Mosaico.
Imposible sin root: namespaces (Docker/Flatpak/bwrap, sandbox de Chromium → `--no-sandbox`), systemd PID 1, módulos, KVM, ver procesos de otras apps.

### Detalle por frente

**glibc + pacman:** glibc 2.43 propia (parches en `glibc/parches/`) que corre binarios de Arch Linux ARM sin recompilar dentro de una app normal: traducción de rutas (`GLIBC_PREFIX`), `execve` vía el cargador `libldp.so`, scripts `#!`, modo `GLIBC_FAKEROOT`, SIGSYS → ENOSYS. **pacman real funciona dentro de la app** (sincroniza, verifica firmas, instala con dependencias). Detalle en las secciones de abajo.

**Terminal dentro de la app (2026-10-19, funciona):** `TerminalActivity` (hoy terminal de rescate: atajo al mantener pulsado el ícono) + `TerminalService` (primer plano, dueño de la sesión). Usa la vista de Termux (`com.github.termux.termux-app:terminal-view:v0.118.3` de JitPack: solo el emulador y `libtermux.so`, que abre el pty) y lanza `libldp.so /usr/bin/bash -l` en `files/archlinux` con `HOME=/home/user`, `PATH=/usr/local/bin:/usr/bin`, `TERM=xterm-256color`. Al abrir escribe `/etc/resolv.conf` con el DNS de Android (+1.1.1.1) y crea `/usr/local/bin/sudo` = `GLIBC_FAKEROOT=1 exec "$@"` (para `sudo pacman ...`). Fila de teclas extra (ESC, TAB, CTRL, ALT, flechas); pellizcar cambia el tamaño de letra; Enter con la sesión terminada cierra la terminal (el servicio sigue si sway corre). `MainActivity` sigue para `correr.sh` (ya no es lanzador).
- **Parche `0004` (termios)**: glibc ≥ 2.42 usa `TCGETS2`/`TCSETS2`, que SELinux no deja usar a las apps sobre `devpts` → `isatty` daba 0 y bash no era interactivo (sin prompt, nano "not a terminal"). Ahora reintenta con `TCGETS`/`TCSETS`. Verificado con `script` dentro de la app: `bash -i` interactivo, `tty`, `stty`.
- **Parche `0005` (SIGSYS protegido)**: bash interactivo instala manejadores para todas las señales fatales, SIGSYS incluida → reemplazaba el de libc y la primera syscall bloqueada por seccomp (`faccessat2` del `test -r` de `/etc/profile`) lo mataba (señal 31). Ahora `sigaction(SIGSYS)` del programa se guarda aparte (recibe solo los SIGSYS que no son de seccomp, ej. `kill -SYS`), y SIGSYS nunca se bloquea (`clear_internal_signals`, también se quita del `sa_mask`): con la señal bloqueada el kernel la forzaría con SIG_DFL.
- **Parche `0006` (/proc sintético)**: SELinux no deja a las apps leer `/proc/stat`, `uptime`, `loadavg`, `version`, `vmstat`, `diskstats` (htop: "Cannot open /proc/stat"). Si `openat` de `/proc/{stat,uptime,loadavg,version}` en lectura da `EACCES`, libc arma el contenido en un `memfd`: inactivo por CPU desde `/sys/devices/system/cpu/cpuN/cpuidle/state*/time` (legible), ocupado = tiempo desde el arranque (`CLOCK_BOOTTIME`) − inactivo (todo como `user`), `btime`, carga de `sysinfo()`, versión de `uname()`. Probado: htop, `uptime`, `ps`. Las apps solo ven sus propios procesos en `/proc` (no tiene arreglo sin root). La terminal pasa `TZ` con la zona de Android.
- Probado en pantalla: prompt `[user@localhost ~]$`, `stty size` = tamaño de la vista, `resolv.conf` con el DNS de la red. Falta: nano/htop a pantalla completa en el teléfono, girar, `sudo pacman -S`. `which` no viene en el Arch mínimo.

**Wayland (2026-10-19, funciona): anfitrión propio + sway anidado.** sway 1.12 / wlroots 0.20.2 / foot de Arch corren tal cual y se ven en la app.
- `wayland/compilar.sh`: libffi 3.5.2 + libwayland-server 1.26.0 estáticas para Android (NDK, meson cruzado) y código de servidor de xdg-shell (`wayland-scanner` del PC) en `wayland/salida/`.
- `app/src/main/cpp/anfitrion.c` (`libanfitrion.so`, CMake desde Gradle): compositor mínimo en bionic con `wl_compositor` v6, `wl_shm` (+XBGR/ABGR), `xdg_wm_base` v2, `wl_seat` v7, `wl_output` v4. Muestra a pantalla completa el último `xdg_toplevel` mapeado: copia el buffer shm (XRGB→RGBX) a la `ANativeWindow` del `SurfaceView` y guarda el último cuadro para redibujar. Tacto = puntero (botón izquierdo). Teclado = códigos evdev sin keymap (`NO_KEYMAP`: el backend wayland de wlroots ignora el keymap del anfitrión y usa el de la config de sway). Hilo propio con `wl_display_run`; Java → cola + `eventfd`.
- Socket `wayland-0` en `<prefijo>/run/user/<uid>` (dentro: `XDG_RUNTIME_DIR=/run/user/<uid>`). Lo arranca la terminal (`Wayland.iniciar`) y `WaylandActivity` (el ícono "Arch Linux": `SurfaceView` + fila ⌨ ESC TAB CTRL ALT SUPER flechas; mapa de teclas Android → evdev, distribución US).
- La terminal exporta `XDG_RUNTIME_DIR`, `WAYLAND_DISPLAY=wayland-0`, `WLR_RENDERER=pixman` y crea `<prefijo>/dev/shm` (`shm_open` de glibc → wlroots fallaba con "Failed to allocate shm file"). `~/.config/sway/config` = `include /etc/sway/config` + `output * scale 2.5`.
- Uso: abrir el ícono "Arch Linux" (sway arranca solo), SUPER y Enter → foot.
- **Entrada** (`WaylandActivity`): toque = clic izquierdo, arrastrar = clic sostenido, mantener 450 ms = clic derecho, dos dedos = scroll (`wl_pointer.axis`, fuente finger, `axis_stop` al soltar). Cursor dibujado por sway (`WLR_NO_HARDWARE_CURSORS=1`; el anfitrión ignora `set_cursor`).
- **Teclado latam**: sway con `xkb_layout latam`; `Distribucion.java` (carácter → evdev + Shift/AltGr) la genera `wayland/generar-teclado.sh` con xkbcommon desde el keymap real (otra distribución: regenerar y cambiar la config de sway). Tildes/diéresis: NFD → tecla muerta + letra; `^` `` ` `` sueltos: tecla muerta + espacio. AltGr = `KEY_RIGHTALT` → Mod5. De teclados virtuales se ignoran los modificadores sueltos (adb/Gboard mandan Shift aparte y se sumaba al de la tabla); Ctrl/Alt se toman del meta state. Teclado físico (el del usuario es US): las teclas con carácter se traducen con la distribución que Android tenga para ese teclado y se pasan a latam con la tabla (el Shift físico se suelta/restaura según pida la tabla); modificadores y teclas sin carácter van crudas por scancode; Alt derecho → Alt (en US no es AltGr). Sin probar todavía con el teclado real. El teclado de Android puede estar en cualquier idioma.
- Probado: símbolos `@#{}[]=*/\|~<>?!^`` ` ``, CTRL+C desde la fila, clic para cambiar foco entre dos foot. Falta probar a mano: scroll con dos dedos, clic derecho, ñ/tildes desde Gboard.
- Limitaciones: popups se cierran al pedirse, sin portapapeles, render por CPU (pixman + copia), sin Xwayland/swaybg, cursor chico. `/dev/shm` es una carpeta en disco (los archivos se borran al crearse; ver si conviene memfd).
- Config de sway en el teléfono (`~/.config/sway/config`): `include /etc/sway/config`, `output * scale 2.5`, `input type:keyboard xkb_layout latam`.

**GPU (2026-10-19, funciona): Turnip + KGSL.** `/dev/kgsl-3d0` abre rw desde la app; `/dev/dri` no. **`/dev/dma_heap/system` sí abre** (bionic y glibc; los `qcom,*` no, por eso antes parecía bloqueado): Turnip reserva memoria exportable (dmabuf) sin ayuda — `turnip/prueba-dmabuf.c` lo comprueba.
- Mesa 26.2.5 (misma versión que Arch ARM) compilada **en el teléfono**, dentro del Arch de la app (gcc 16.1.1, meson, ninja; 725 pasos en 6 min): `turnip/compilar-mesa.sh` → `~/compilar-mesa.sh`, se corre desde la terminal (servicio en primer plano: Android no congela el proceso) con `bash ~/compilar-mesa.sh > ~/mesa.log 2>&1 &`. Fuente en `~/src/mesa-26.2.5.tar.xz` (se baja en el PC y se copia). Solo Vulkan freedreno, `-Dfreedreno-kmds=kgsl,msm -Dplatforms=wayland`, `debugoptimized` (aserciones + líneas para gdb), sin GL/gallium/LLVM. **Ojo `kgsl,msm`**: con solo `kgsl` Mesa deja fuera libdrm a propósito (`meson.build`: `system_has_kms_drm = false`) y la WSI no tiene imágenes DRM/dmabuf → con dmabuf disponible `vkcube` saltaba a basura (SIGBUS; con aserciones: `get_blit_type: Invalid image type`). msm no se usa (no hay `/dev/dri`). Instalado en `~/turnip`. Dependencias de compilación instaladas con pacman: gcc make meson ninja pkgconf bison flex python-mako python-yaml python-packaging libdrm wayland-protocols glslang vulkan-tools.
- `vulkaninfo`: `Turnip Adreno (TM) 619`, Vulkan 1.3, Mesa 26.2.5. `vkcube` se ve dentro de sway: render en la GPU y presentación por `wl_shm` (`MESA_VK_WSI_DEBUG=sw`: Mesa copia el cuadro a memoria compartida; sin dmabuf no hay otra).
- La terminal exporta `VK_ICD_FILENAMES` (Turnip) y `MESA_VK_WSI_DEBUG=sw`.
- **OpenGL (Zink, 2026-10-19, funciona):** el `mesa` 26.2.5 de Arch (instalado como dependencia de wlroots, con libglvnd) ya trae Zink; carga Vulkan con el loader, así que usa nuestro Turnip sin recompilar Mesa. Surfaceless: `GALLIUM_DRIVER=zink eglinfo -B -p surfaceless` → `zink Vulkan 1.3 (Turnip Adreno 619)`. En Wayland sin dmabuf, EGL solo sirve por el camino "swrast" (`wl_shm`) y ahí usa Zink con **kopper** (presenta por la WSI de Vulkan → `wl_shm` con `MESA_VK_WSI_DEBUG=sw`) solo si ve `MESA_LOADER_DRIVER_OVERRIDE=zink` **y** `LIBGL_ALWAYS_SOFTWARE=1` (`platform_wayland.c`, `eglapi.c`). Pero Zink lee la misma variable y exige una GPU de CPU ("CPU device requested but none found"); sin ella EGL reintenta sin Zink y carga zink como driver "sw" → **cuadros negros**. Arreglo: `turnip/egl-zink.c` (LD_PRELOAD, intercepta `getenv` y le dice `LIBGL_ALWAYS_SOFTWARE=1` solo a `libEGL_mesa`). Sobrevive a `pacman -Syu` (no hay Mesa propio para GL). Lo compila `compilar-mesa.sh` en `~/turnip/lib/libegl-zink.so` (fuente en `~/src/egl-zink.c`). `mesa-utils` instalado (eglinfo, es2gears_wayland). Con llvmpipe (`LIBGL_ALWAYS_SOFTWARE=1` sin Zink) también anda, por CPU.
- **dmabuf (2026-10-19, funciona):** el anfitrión ofrece `zwp_linux_dmabuf_v1` v3 (sin feedback → la WSI asume misma GPU), formatos ARGB/XRGB/ABGR/XBGR, solo modificador LINEAR y un plano. Al hacer commit espera la fence implícita (`poll` POLLIN), `DMA_BUF_IOCTL_SYNC` y copia directo del mmap a la ventana (una sola pasada; ventana en formato BGRA = `HAL_PIXEL_FORMAT_BGRA_8888` (5) para no convertir píxel a píxel). El último dmabuf queda retenido (release al llegar el siguiente) para redibujar si la ventana se recrea. Probado directo al anfitrión sin `MESA_VK_WSI_DEBUG=sw`: `vkcube` y `es2gears_wayland` (Zink), ~60 fps. CPU en 15 s de vkcube: cliente 0.7 s (antes ~3–6 s con `sw`), anfitrión ~7 s (con shm ~5.5 s: leer memoria escrita por la GPU obliga a invalidar caché); total ~30 % menos. **Dentro de sway sigue `MESA_VK_WSI_DEBUG=sw`** (la terminal lo exporta): sway con pixman no ofrece dmabuf a sus clientes.
- **Cero copias (2026-10-19, funciona):** protocolo propio `wayland/android-ahb-v1.xml`: el cliente pide un `wl_buffer` (ancho, alto, fourcc) y el anfitrión reserva un `AHardwareBuffer` (`GPU_COLOR_OUTPUT | GPU_SAMPLED_IMAGE | COMPOSER_OVERLAY`) y le manda su dmabuf (evento `listo`: fd, offset, stride). El dmabuf se saca con `AHardwareBuffer_sendHandleToUnixSocket` por un socketpair (formato de `GraphicBuffer::flatten`; con gralloc de Qualcomm el 1er fd es el buffer, el 2º metadatos). Gralloc lo da **lineal** (flags `0x100288`, sin `0x08000000` = UBWC), stride 1088 px; acepta ABGR/XBGR (RGBA_8888/RGBX_8888) y ARGB/XRGB (formato HAL 5, BGRA). Al hacer commit, el `AHardwareBuffer` va a SurfaceFlinger con `ASurfaceTransaction_setBuffer` sobre una capa hija del `SurfaceView` (`ASurfaceControl_createFromWindow`); la capa se oculta cuando llega un cuadro shm/dmabuf (camino por CPU, que sigue para sway). Sincronización implícita: acquire fence = `DMA_BUF_IOCTL_EXPORT_SYNC_FILE` (READ) del dmabuf; la release fence de SurfaceFlinger (`ASurfaceTransactionStats_getPreviousReleaseFenceFd`, en `OnComplete`) se le pega al dmabuf con `IMPORT_SYNC_FILE` (READ) antes de `wl_buffer.release`: nadie espera con la CPU. **Frame callbacks**: en el primer vsync (`AChoreographer`, hilo propio con `ALooper`) después de `OnCommit`; con `OnComplete` el cliente iba a la mitad de los fps, y con `OnCommit` solo, sin freno (158 fps en pantalla de 48 Hz: cuadros descartados). La pantalla es variable (30–144 Hz): sube a 144 cuando hay movimiento.
  - **Parche a Mesa** `turnip/parches/0001-wsi-android-ahb.patch` (WSI de Wayland, `wsi_common_wayland.c` + el XML): tipo `WSI_WL_BUFFER_AHB` si el anfitrión ofrece `android_ahb_v1` (no en modo `sw`, no con sync explícito, formatos de 8 bits RGBA/BGRA): configura la imagen como la nativa con modificador LINEAR, pide al anfitrión un buffer por imagen (un roundtrip), cambia la lista de modificadores por el layout explícito (stride del anfitrión) y `create_mem` importa el dmabuf (`image->dma_buf_fd` = ese fd, así la sincronización implícita de la WSI funciona igual). `MESA_WSI_AHB=0` lo desactiva (vuelve a linux-dmabuf). Vale para Vulkan y para GL (Zink presenta por la WSI de Turnip). `compilar-mesa.sh` aplica `~/src/parches/*.patch` con `git apply` (marca `.aplicado-*`); recompilar solo la WSI toma ~12 s.
  - Medido (12 s, ventana 1080×1134, CPU de todo el proceso de la app): vkcube 5,95 s → 1,32 s; es2gears_wayland 6,62 s → 1,24 s. Cliente de prueba mínimo (`turnip/prueba-ahb.c`, limpia con colores): 3–9 % de CPU a 84–158 fps.
  - Probado a mano por el usuario: cambiar el tamaño (abrir/cerrar el teclado: la swapchain se recrea y pide buffers nuevos) ✅; salir de la app y volver: el programa sigue corriendo en segundo plano y se vuelve a ver ✅. Sin ventana, los frame callbacks se responden al tiro (el cliente sigue dibujando: gasta batería en segundo plano, a revisar).
- Depurar clientes: `gdb` instalado en el Arch de la app; `info sharedlibrary` no ve las bibliotecas (cargador propio): leer `/proc/<pid>/maps` desde python de gdb y simbolizar en el PC con `llvm-symbolizer` del NDK.
- Keymap: `es2gears_wayland` (eglut) abortaba con `NO_KEYMAP`; el anfitrión ahora manda el keymap xkb latam compilado (`app/src/main/cpp/keymap.h`, generado por `wayland/generar-teclado.sh`) en un memfd sellado. wlroots lo ignora igual.

**Escritorio por GPU (2026-10-19, funciona): wlroots 0.20.2 parchado.** Se compila en el teléfono (`wlroots/compilar-wlroots.sh`, ~30 s) y se instala en `~/wlroots`; sway de Arch lo usa tal cual con `LD_LIBRARY_PATH` (el script comprueba que la biblioteca exporte todos los símbolos de la de Arch: sway se enlaza con `-z now`). Parches en `wlroots/parches/`:
- `0001-vulkan-sin-drm`: con `WLR_RENDERER=vulkan` y sin fd DRM, `renderer_autocreate` crea igual el renderer Vulkan y `vulkan_find_drm_phdev(-1)` toma el primer dispositivo (Turnip; no tiene `VK_EXT_physical_device_drm`, las otras 7 extensiones que pide wlroots sí). El renderer queda sin fd DRM (sin timeline/syncobj; sincronización implícita sí: "Implicit sync interop supported").
- `0002-allocator-ahb`: allocator en el backend wayland (`backend/wayland/ahb.c`) que pide cada buffer al anfitrión por `android-ahb-v1` (roundtrip en la `busy_loop_queue`, LINEAR). `wlr_allocator_autocreate` lo prueba primero si el renderer usa dmabuf; `create_wl_buffer` reutiliza el `wl_buffer` del anfitrión en vez de importarlo por linux-dmabuf. sway compone en la GPU directo en el AHardwareBuffer que va a SurfaceFlinger.
- `0003-dmabuf-sin-drm`: sway solo crea linux-dmabuf si el renderer tiene fd DRM → sin él, la WSI de Mesa (fuera de modo `sw`) no encuentra formatos y `vkCreateSwapchainKHR` falla (vkcube daba segfault en `vkGetSwapchainImagesKHR`). Ahora `wlr_renderer_init_wl_shm` crea además linux-dmabuf **v3** (formatos por eventos `modifier`, sin feedback ni `main_device`) cuando el renderer no tiene fd DRM pero importa dmabuf. Formatos: LINEAR y UBWC (`0x0500000000000001`).
- Anfitrión: `setGeometry` dejaba la escala del primer buffer (sway manda uno de 1280×720 antes del configure → se veía estirado); ahora `geometria()` usa `setCrop` + `setPosition` + `setScale` en cada transacción.
- Medido (`scripts/test-cpu-sway.sh`, vkcube dentro de sway, 10 s): pixman + shm: app 3,73 s + sway 3,96 s + vkcube 1,20 s = 8,9 s; GPU: 1,21 + 0,63 + 0,29 = 2,1 s. es2gears (Zink) dentro de sway ✅.
- Editar los parches: árbol con git en `trabajo/wlroots/wlroots-0.20.2` (commit base = tarball), `git diff` por archivos; los parches se aplican en orden (0003 se generó contra el árbol con 0001). Para recompilar desde cero en el teléfono, borrar `~/src/wlroots-0.20.2`.

**sway, swayfx y Hyprland (2026-10-19, medido):** `scripts/test-medir-wm.sh` (WM = sway | swayfx | swayfx-plano | hyprland, se reemplaza `@WM@` con sed) mide RAM del compositor y CPU de 10 s en reposo y con vkcube.

| | RAM (RSS) | Reposo (10 s) | Con vkcube (10 s: app + compositor + vkcube) |
|---|---|---|---|
| sway (Vulkan, wlroots parchado) | 19 MB | app 30 ms, sway 30 ms | 1,13 + 0,90 + 0,36 = 2,4 s |
| swayfx sin efectos (GLES por Zink) | 58 MB | app 170 ms, swayfx 120 ms | 1,06 + 1,47 + 0,37 = 2,9 s |
| swayfx con efectos (radio 12, sombras, blur, dim) | 60 MB | app 30 ms, swayfx 60 ms | 1,02 + 1,73 + 0,37 = 3,1 s |

- **swayfx 0.6** (AUR; scenefx 0.5 está en extra y usa wlroots0.20): `swayfx/compilar-swayfx.sh` (36 s en el teléfono, instala en `~/swayfx`, no reemplaza al sway de Arch); `scripts/subir-swayfx.sh` + `TIEMPO=900 scripts/correr.sh sdk36 scripts/test-compilar-swayfx.sh`. scenefx solo tiene renderer GLES2: con `WLR_RENDERER_FORCE_SOFTWARE=1 GALLIUM_DRIVER=zink` crea EGL con el dispositivo "software" de Mesa (`EGL_PLATFORM_DEVICE_EXT`), que con esa variable es **Zink sobre Turnip** (con import de dmabuf LINEAR y UBWC). Usa nuestro wlroots parchado tal cual (`LD_LIBRARY_PATH=~/wlroots/lib`): allocator android-ahb-v1 y linux-dmabuf v3 para clientes. Sin parches nuevos. Config con efectos: `~/.config/swayfx/config` (`include ~/.config/sway/config` + `corner_radius 12`, `shadows enable`, `blur enable`, `default_dim_inactive 0.2`). Correr: `WLR_RENDERER_FORCE_SOFTWARE=1 GALLIUM_DRIVER=zink LD_LIBRARY_PATH=~/wlroots/lib ~/swayfx/bin/sway -c ~/.config/swayfx/config`. El RAM extra es Mesa GL + Zink cargados en el proceso.
- **Hyprland 0.56.2** (extra, instalado en la app con `pacman -S hyprland`, 24 paquetes; config nueva en Lua `~/.config/hypr/hyprland.lua`): aborta en `CBackend::create()`: aquamarine pide `xdg_wm_base` v6 (el anfitrión da v2), `wl_seat` v9 (v7) y `zwp_linux_dmabuf_v1` v4 (v3). Aunque se arreglen las versiones, todo supone DRM: aquamarine solo tiene allocator GBM (sin fd DRM: "no allocator available"), el renderer de Hyprland abre EGL desde el fd DRM (`CHyprOpenGLImpl()`: `eglDeviceFromDRMFD` o GBM) y su linux-dmabuf v4 se desactiva sin dispositivo DRM (`LinuxDMABUF.cpp`). Para hacerlo andar: (1) aquamarine: bind con la versión ofrecida + allocator android-ahb-v1 (como `wlroots/parches/0002`) + reutilizar el `wl_buffer` del anfitrión; (2) Hyprland: EGL con el dispositivo software (Zink) sin fd DRM y linux-dmabuf sin `main_device`; compilar ambos en el teléfono. Fuentes en `trabajo/hypr/` (aquamarine-0.15.1, hyprland-source). También: "Couldn't bind the Hyprland Socket 2" (IPC; sin investigar). Se quita con `sudo pacman -Rns hyprland`.

**Escritorio estilo HyDE (2026-10-19, funciona):** config de sway en `sway/` del repo, copiada al teléfono con `scripts/subir-sway.sh` (la anterior quedó en `~/.config/sway/config.anterior`); paquetes con `TIEMPO=600 scripts/correr.sh sdk36 scripts/test-sway-config.sh` (waybar fuzzel swaybg wl-clipboard cliphist autotiling jq ttf-jetbrains-mono-nerd kitty ttf-cascadia-code-nerd). Sacada de la config de Hyprland del PC (HyDE en `~/.local/share/hypr/lua/`, tema "Mine", overrides en `~/.config/hypr/hyprland.lua`).
- Atajos de HyDE: SUPER+T/Enter kitty (SUPER+ALT+T foot), Q cerrar, W flotar, SHIFT+F11 pantalla completa, SUPER+SHIFT+F fijar (sticky), G pestañas (≈ grupos), J alternar división, flechas foco, +SHIFT redimensionar, +SHIFT+CTRL mover, X modo redimensionar, A fuzzel, TAB selector de ventanas (`ventanas.sh`), V portapapeles (cliphist), / lista de atajos (`atajos.sh`), 1–0 / SHIFT / ALT escritorios, CTRL+←/→ escritorio anterior/siguiente, CTRL+↓ primer escritorio vacío (`escritorio-vacio.sh`), S scratchpad (= escritorio especial), Delete salir.
- Aspecto: sin bordes, huecos 1 px (overrides del usuario), colores Graphite Mono, fondo negro (el fondo de HyDE es negro liso), opacidad 0.90 activa / 0.75 inactivas / 1 pantalla completa con `opacidad.py` (i3ipc, por IPC; sway no tiene opacidad por foco; **sin confirmar** que se aplique: en una captura las ventanas inactivas no se veían más tenues), dwindle con `autotiling` (en `ps` aparece como `python`). Reglas de ventanas flotantes/PiP/modales de `window_rules.lua`.
- waybar (`sway/waybar/`): píldoras negras del layout 12 de HyDE, escritorios a la izquierda, CPU/memoria/reloj a la derecha. El centro va vacío: la cámara está en x 505–575, y 0–127 (`dumpsys display`, DisplayCutout). La batería no se puede leer (`/sys/class/power_supply`: Permission denied). waybar (GLib) aborta sin bus de sesión D-Bus (intenta `dbus-launch`): `sway/dbus-sesion.sh` va a `/etc/profile.d` y arranca `dbus-daemon --session` en `$XDG_RUNTIME_DIR/bus` (una vez; sway, terminal y foot lo comparten; el servicio lanza sway con `bash -l`).
- kitty: la config del PC tal cual (`sway/kitty/`: kitty.conf, hyde.conf, theme.conf; CaskaydiaCove Nerd Font Mono 9, padding 25, cursor_trail). OpenGL por Zink. Necesitó el parche **`0007` de glibc**: el lanzador de kitty busca `../lib/kitty` desde `/proc/self/exe`, que el kernel apunta a `libldp.so`. Ahora `readlink` de `/proc/self/exe`, `/proc/thread-self/exe` y `/proc/<pid propio>/exe` devuelve el programa (`AT_EXECFN`, que rtld.c llena con la ruta que recibió el cargador; `l_name` del mapa principal queda en `""`, no sirve). Solo en libc.
- **Modo inmersivo** (`WaylandActivity.inmersivo()`): sin barras de Android (se asoman deslizando desde el borde, `BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE`) y dibujando bajo la cámara (`LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS`). sway recibe el panel en píxeles reales: 1080×2193 (2340 menos la fila de teclas) con el teclado cerrado; `scale 2.5` solo agranda la interfaz, los buffers ya son de resolución nativa.

**Steam (idea, sin empezar):** no hay multilib en ARM (multilib = libs i686 del Arch x86_64) y Steam es solo x86. Camino: FEX-Emu (emulador x86/x86_64 con JIT, en espacio de usuario; lo que usa Valve en ARM) + rootfs x86_64 con Steam. El teléfono es solo 64 bits (`ro.product.cpu.abilist32` vacío) → box86 descartado. El usuario dice que ya hay cliente oficial de Steam para ARM (a revisar). Requisitos antes: Xwayland, GPU (Turnip; FEX pasa GL/Vulkan al Mesa nativo con thunks). Ojo: FEX hace las syscalls del invitado directo (no pasan por el traductor de rutas de la glibc), usa su propio RootFS. Repos de Arch ARM: core, extra, alarm, aur (no hay fex/box64; sí qemu-user).

**Comandos:**
- Repo git en `..` (raíz `Android/`): fuera del repo quedan los generados (árbol `glibc/glibc-2.43/`, `glibc/build`, `glibc/salida`, `wayland/{fuentes,build,salida}`, `trabajo/`); todo se reconstruye con los scripts.
- Compilar la app: primero `wayland/compilar.sh` (una vez, y de nuevo si cambia la lista de protocolos: genera xdg-shell y linux-dmabuf; bibliotecas Wayland para el anfitrión), luego `./gradlew assembleSdk36Debug && adb install -r app/build/outputs/apk/sdk36/debug/app-sdk36-debug.apk`. Reinstalar cierra la terminal, sway y todo lo que corra en la app.
- Tabla de teclado: `wayland/generar-teclado.sh [distribución]` (y cambiar `xkb_layout` en la config de sway).
- Turnip: `turnip/compilar-mesa.sh` se copia a `~/` del Arch de la app junto con `~/src/mesa-26.2.5.tar.xz` y se corre desde la terminal (ver "GPU"). `scripts/subir-mesa.sh` copia el script, `egl-zink.c` y `turnip/parches/`; `TIEMPO=900 scripts/correr.sh sdk36 scripts/test-compilar-mesa.sh` lo corre por ADB (incremental). Editar el parche: árbol de Mesa con git en `trabajo/mesa/mesa-26.2.5` (commit base = original), `git diff > turnip/parches/0001-...patch`.
- Cero copias: `scripts/subir-ahb.sh` + `scripts/correr-wl.sh scripts/test-ahb.sh x.png` (cliente mínimo), `ESPERA=55 TIEMPO=150 scripts/correr-wl.sh scripts/test-cpu-ahb.sh x.png` (vkcube/es2gears, ahb vs dmabuf).
- wlroots: `scripts/subir-wlroots.sh [sin-tarball]` y `TIEMPO=600 scripts/correr.sh sdk36 scripts/test-compilar-wlroots.sh`. Probar: `ESPERA=30 TIEMPO=90 scripts/correr-wl.sh scripts/test-sway-vulkan.sh x.png` (reemplaza el sway del servicio, abre foot y vkcube), `ESPERA=45 TIEMPO=120 scripts/correr-wl.sh scripts/test-cpu-sway.sh x.png` (pixman vs GPU).
- Recompilar glibc: `glibc/compilar.sh` (Docker; incremental; baja el tarball y aplica los parches si falta el árbol). **Si se agregan archivos `.c` nuevos a sysdeps, borrar `glibc/build/` antes** (la lista de stubs de syscalls se genera una vez).
- Verificar que ninguna syscall con rutas se escape del traductor: `glibc/verificar.sh`.
- Instalar la glibc nueva en el teléfono: `scripts/instalar-glibc.sh sdk36 archlinux` (APK con `libldp.so` + bibliotecas en el prefijo).
- Correr algo dentro de la app: `TIEMPO=<segundos> scripts/correr.sh sdk36 <script.sh>` (ej. `scripts/test-pacman.sh`, `scripts/test-rutas.sh`).
- Editar los parches: el árbol `glibc/glibc-2.43/` ya tiene los 7 aplicados. Para guardar cambios nuevos, generar `0008-...patch` con `diff -u --label a/F --label b/F` contra un árbol tarball + parches 0001–0007 (ojo: `diff -rq` sale en español, usar `LC_ALL=C` para listar archivos), y comprobar que los parches reproducen el árbol exacto (así se hizo con 0002 y 0003).

**Tropiezos (para no repetir):**
- En los scripts que corre la app, **no exportar `PATH=/usr/bin`** para el `sh` de Android: rompe `mkdir`, `id`, `grep`… Ponerlo solo delante del comando glibc (`PATH=/usr/bin $L /usr/bin/bash -c '...'`).
- `correr.sh` deja de esperar cuando ve `=== fin` **o la palabra `error`** en la salida; para procesos largos subir `TIEMPO`.
- El rastreador ptrace no veía los SIGSYS de `faccessat2`/`accept`: para diagnosticar usar `GLIBC_DEBUG_SIGSYS=1`.
- Un proceso colgado de la app se ve con `adb shell "ps -A -o PID,STAT,TIME,ARGS -u u0_a294"` y se detiene con `adb shell "run-as dev.ben4shot.glibcprueba.sdk36 kill <pid>"` (el `/proc/<pid>` de la app no se puede leer por ADB).
- Para probar clientes Wayland por ADB sin sway: abrir `WaylandActivity` (arranca el anfitrión), luego `MainActivity` sin `force-stop` (mismo proceso) con `WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR=/run/user/$(id -u)`, volver a `WaylandActivity` y `adb exec-out screencap -p`.
- `ps` muestra `libldp.so --argv0 ...` en los argumentos; el nombre corto (`comm`) sí es el del programa.

## La idea

Convertir el Redmi 15 5G en un sistema **completamente modificable, con soporte real y nativo para programas de Linux** (glibc, paquetes de Arch Linux ARM sin recompilar), sin perder las funciones importantes de Android: apps bancarias chilenas, Play Store, cámara, pagos, etc.

Si fuera solo por gusto, se reemplazaría HyperOS. No se hace porque se perderían esas funciones.

Relación con los otros frentes del repo (ver `../NOTAS.md`):
- **Debloat** (`../debloat/`): ya hecho, por ADB y reversible.
- **Mosaico** (`../mosaico/`): launcher estilo Hyprland (escritorios, mosaico de ventanas, barra tipo waybar, buscador tipo rofi). Las ventanas de los programas Linux deberían integrarse ahí como ventanas Android normales.

## Qué se espera

- Correr binarios **glibc reales** de Arch Linux ARM tal cual vienen (`pacman`-like), a **velocidad nativa**.
- **Sin root, sin proot, sin emulación, sin Termux.** El usuario no quiere Termux ni proot: los considera "no reales".
- Procesos hijos, hilos, señales, pipes, servicios de usuario: todo lo que es espacio de usuario.
- Gráficos acelerados por GPU (Vulkan/OpenGL) y apps gráficas Linux (Wayland), integradas como ventanas Android (recientes, pantalla dividida, flotante, Mosaico).
- Todo reversible: es una app, se desinstala y el teléfono queda igual.

### Qué queda fuera (límites duros sin root)
- Contenedores/namespaces (Docker, Flatpak, bubblewrap): Android no se los permite a las apps.
- Módulos de kernel, drivers, iptables, montar discos.
- Crear `/usr`, `/lib`, `/etc` reales: la raíz es de solo lectura y verificada (dm-verity).
- Acceso a archivos privados de otras apps.
- Reemplazar SystemUI/pantalla de bloqueo (siguen siendo de HyperOS).
- systemd como PID 1 (se usaría un supervisor simple tipo runit/s6 dentro de la app).
- SysV IPC (`shmget`, etc.): el kernel de Android no lo trae; necesitaría capa de compatibilidad.

## El teléfono

| | |
|---|---|
| Modelo | Redmi 15 5G, `25057RN09G`, codename `spring`, `spring_global` (región CL) |
| Sistema | HyperOS `OS3.0.304.0.WOUMIXM`, Android 16 (SDK 36), parche 2026-09-01 |
| SoC / GPU | Qualcomm SM6375 (Snapdragon 6s Gen 3) / **Adreno 619** (`/dev/kgsl-3d0`) |
| Kernel | `6.1.157-android14-11` (GKI 6.1) |
| RAM | 8 GB |
| Bootloader | **bloqueado**, arranque verde |
| Particiones | A/B, dinámicas, con `init_boot` |
| Virtualización | **sin hipervisor** (`/dev/kvm` no existe): la "Terminal Linux" de Android 16 viene instalada pero no sirve |

## Decisiones tomadas (y por qué)

1. **No root.** Se evaluó en detalle:
   - Las apps bancarias revisan el estado del bootloader con certificación por hardware (Play Integrity `DEVICE`/`STRONG`, key attestation). Esconderlo depende de llaves filtradas (TrickyStore + `keybox.xml`) que Google revoca: es una carrera constante.
   - **Root temporal no sirve**: lo que habría que cambiar (`/usr`, `/lib`) vive en particiones verificadas; para que persista el bootloader debe quedar desbloqueado. Desbloquear y volver a bloquear borran `/data` cada vez.
   - Si algún día se quisiera: Xiaomi exige permiso en la app Xiaomi Community, cuenta con antigüedad, 1 equipo/año, espera de 72–168 h y Mi Unlock (solo Windows). El root sería KernelSU parchando `init_boot`. Volver atrás: fastboot ROM Global oficial con MiFlash "clean all and lock" (misma región, versión ≥ la actual por anti-rollback).
2. **No Termux / proot.** Termux no es emulado (binarios ARM nativos sobre Bionic), pero el usuario quiere glibc real. proot intercepta syscalls con ptrace: lento en disco/procesos.
3. **No reemplazar Android** (postmarketOS, Droidian): se pierden los bancos, y el Redmi 15 es muy nuevo (no hay ports).
4. **Camino elegido: glibc nativa dentro de una app normal**, con una glibc propia parchada (ver Arquitectura).
5. Para Mosaico (manejo de ventanas existentes) la opción sin root es **Shizuku** (permisos de ADB para la app; se reinicia tras cada reinicio del teléfono vía Depuración inalámbrica). Aún no se instala.

## Lo que se probó (y funcionó)

App de prueba en este directorio, con dos variantes: `dev.ben4shot.glibcprueba.sdk28` y `.sdk36`. Al abrirse ejecuta `files/test.sh` desde el proceso de la app (con su seccomp y SELinux reales) y escribe la salida en logcat con el tag `GLIBC`.

Paquetes usados: glibc 2.43, bash 5.3.20, coreutils 9.12, gcc-libs, readline, ncurses, acl, attr, gmp, libcap, openssl (Arch Linux ARM, `aarch64/core`).

| Prueba | Resultado |
|---|---|
| Como `shell` de ADB: `ld-linux-aarch64.so.1 --library-path ... bash` | ✅ funciona tal cual |
| Hijo glibc lanzado desde bash glibc (sin parchar) | ❌ `required file not found`: busca `/lib/ld-linux-aarch64.so.1` |
| Hijos con `patchelf --set-interpreter <prefijo>/... --force-rpath --set-rpath <prefijo>/usr/lib` | ✅ (con RUNPATH no basta: no es transitivo, `libreadline` no encuentra `libncursesw`) |
| App targetSdk 36, ejecutar desde `files/` | ❌ `Permission denied` (W^X: SELinux bloquea `execve` desde la carpeta de datos) |
| App targetSdk 36, **cargador en `jniLibs` como `libld.so`** (`useLegacyPackaging = true`) y todo lo demás en `files/` | ✅ funciona: W^X solo bloquea `execve`, no el `mmap` ejecutable que hace el cargador |
| App (cualquier targetSdk) sin más | ❌ `Bad system call`: seccomp de apps mata con SIGSYS |
| Syscalls bloqueadas (detectadas con `tracer/`) | Solo **2**: `set_robust_list` (nr 99) y `rseq` (nr 293). Bionic no las usa |
| `GLIBC_TUNABLES=glibc.pthread.rseq=0` | ✅ elimina `rseq`; solo queda `set_robust_list` |
| Con esas 2 convertidas en `ENOSYS`: fork/exec, pipes, hilos (`sort --parallel`), stat, cp, mktemp, date, sleep, `timeout` (señales) | ✅ todo funciona |
| `id` | ⚠️ solo números: no hay `/etc/passwd` → falta traducción de rutas |
| Enlaces duros (terminfo) | ⚠️ Android no deja crearlos → el instalador debe convertirlos en copias |

Diferencias de contexto: `shell` (ADB) no tiene filtro seccomp; las apps sí (`Seccomp: 2`). Dominios SELinux: `untrusted_app_27` (sdk28) y `untrusted_app` (sdk36).

### glibc propia (2026-10-19)

`glibc/compilar.sh` compila glibc 2.43 (tarball oficial de GNU, misma versión que Arch ARM) en un contenedor Docker `archlinux` con `aarch64-linux-gnu-gcc` (GCC 16.2). Mismas opciones que Arch: `--prefix=/usr`, todo en `/usr/lib` (`configparms`). Resultado en `glibc/salida/`.

Parche `glibc/parches/0001-android-seccomp.patch`:
- aarch64 deja de asumir `set_robust_list` (`#undef __ASSUME_SET_ROBUST_LIST`, como arm/mips/riscv) y no se llama al iniciar → `__nptl_set_robust_list_avail = false`. glibc recorre la lista robusta en espacio de usuario al salir un hilo. Efecto: los mutex robustos **compartidos entre procesos** dan `ENOTSUP` (los normales funcionan).
- `_Fork`: el hijo solo llama `set_robust_list` si está disponible (sin esto, todo hijo de `fork` moría con SIGSYS).
- Tunable `glibc.pthread.rseq` por defecto en 0.

| Prueba (`scripts/test-glibc-propia.sh`, app sdk36, cargador `libldp.so`, libs en `files/glibcp/`) | Resultado |
|---|---|
| bash + hijos: ls, nproc, `sort --parallel`, stat, cp, date, `timeout` (señales), **sin rastreador y sin GLIBC_TUNABLES** | ✅ todo funciona |

El resto de los paquetes de Arch (bash, coreutils...) corren sin recompilar sobre esta glibc.

### Traducción de rutas y execve (2026-10-19)

Parche `glibc/parches/0002-android-rutas.patch`. Se activa con `GLIBC_PREFIX=<dir>` en el entorno; sin esa variable, glibc se comporta normal.

- **Un solo punto**: `INTERNAL_SYSCALL_RAW` de aarch64 (`sysdep.h`). Si el número de syscall es de las que llevan rutas, llama a `__android_path_syscall` (`sysdeps/unix/sysv/linux/aarch64/android-path.c`); con número constante el compilador quita la comprobación en el resto. Va compilado en libc **y en ld.so**, así el cargador también encuentra `/usr/lib` en el prefijo (ya no hace falta `--library-path` ni `patchelf`).
- Las llamadas cancelables (`open`, `connect`...) entran por `__internal_syscall_cancel` (`nptl/cancellation.c`) con el número en tiempo de ejecución: ahí también se desvían.
- 18 syscalls que eran stubs en ensamblador (`execve`, `chdir`, `readlinkat`, `mkdirat`, `unlinkat`, `symlinkat`, `linkat`, `fchownat`, `chroot`, xattr, `inotify_add_watch`) pasan a C en `sysdeps/.../aarch64/` para que usen la macro. `glibc/verificar.sh` desensambla libc y ld.so y lista syscalls con rutas fuera del traductor: solo quedan `acct` y `name_to_handle_at`.
- **Reglas**: ruta absoluta → `<prefijo><ruta>`, salvo `/proc /sys /dev /data /system /apex /vendor /product /odm /system_ext /storage /sdcard /linkerconfig`. `/dev/shm` sí se traduce. Las relativas no se tocan.
- **Al revés**: `getcwd` y `readlinkat` quitan el prefijo (también su forma canónica `/data/data/...`, que es la que devuelve el kernel). `symlinkat` traduce el destino absoluto, así el kernel lo resuelve dentro del prefijo.
- **Sockets Unix**: `bind`/`connect` traducen `sun_path` (máx. 108 bytes en total).
- **execve**: abre el archivo; `#!` → lanza el intérprete (como el kernel, un argumento); ELF con intérprete `ld-linux` → `cargador --argv0 <argv0> <programa>`; cualquier otro (bionic, `/system/bin/...`) → execve normal. Revisa `X_OK`. `execveat` relativo a un descriptor pasa por `/proc/self/fd/N`.
- **Entorno**: prefijo y cargador se leen de `/proc/self/environ` (el entorno inicial, así `clearenv` no los pierde). execve reinyecta `GLIBC_PREFIX`/`GLIBC_LOADER` si faltan (ej. `env -i`). Cargador: `GLIBC_LOADER` o `/proc/self/exe`.
- ld.so pone el nombre del programa al proceso (`prctl(PR_SET_NAME)`), si no `ps`/`top` mostrarían `libldp.so`.
- `posix_spawn`: pila del hijo de 32 → 64 KiB (execve usa ~10 KiB de buffers).

| Prueba (`scripts/test-rutas.sh`, prefijo `files/arch`, `scripts/instalar-glibc.sh`) | Resultado |
|---|---|
| `ls /` muestra el prefijo; `/etc/passwd` → `id`/`whoami` con nombre | ✅ |
| Buscar en `PATH`, `cd /usr/lib` + `pwd` y `/bin/pwd`, `cd ~`, `readlink -f /bin/sh` | ✅ (rutas virtuales) |
| Scripts `#!/usr/bin/bash` y `#!/usr/bin/env bash` | ✅ |
| `ln -s /usr/bin/date` y ejecutar el enlace; `mkdir -p`/`mv`/`rm -r` | ✅ |
| `env -i bash` (reinyección del prefijo) | ✅ |
| `/proc` sin traducir, `comm` del proceso = nombre del programa | ✅ |
| Ejecutar un binario de Android (`/system/bin/toybox`) | ✅ |
| Hilos, señales, errores (`No such file`, `command not found`) | ✅ |

Límites conocidos:
- Lo que hace syscalls sin pasar por glibc (Go, binarios estáticos, `syscall()`) no se traduce.
- Las syscalls con rutas no son puntos de cancelación (`pthread_cancel` no interrumpe un `open`).
- `/proc/self/exe` apunta al cargador y `/proc/<pid>/cmdline` muestra los argumentos del cargador.
- Enlaces simbólicos absolutos que vienen dentro de los paquetes: el kernel los resuelve tal cual → el instalador debe reescribirlos (si extrae con un programa glibc, `symlinkat` ya lo hace solo). Relativos que salen hacia `/proc` (ej. `/etc/mtab -> ../proc/self/mounts`) apuntan dentro del prefijo.
- El rootfs de prueba no trae el paquete `filesystem` (faltaban `/bin`, `/lib`, `/tmp`, `/etc/passwd`: los crea el test).

### pacman real dentro de la app (2026-10-19)

**pacman 7.1 de Arch Linux ARM funciona dentro de la app**: `pacman -Sy`, resolver dependencias, bajar, verificar firmas (`Validated By: Signature`), instalar, hooks. Probado instalando `nano`, `htop` y `git` (con perl y 6 dependencias más); `git init` funciona.

**Bootstrap** (`scripts/instalar-arch.sh [sdk36]`):
1. `scripts/bootstrap.py` (en el PC): lee `core`/`extra`/`alarm` de Arch ARM, resuelve dependencias (incluye `provides`/sonames), baja y verifica sha256 (caché en `~/.cache/glibc-prueba`), y escribe un tar con: el contenido de los paquetes (enlaces duros → copias; enlaces absolutos → con el prefijo del teléfono), la base de datos local de pacman (`var/lib/pacman/local/*/{desc,files,mtree,install}`), la glibc propia encima y `pacman.conf` ajustado. Por defecto instala `base` + `pacman` + `archlinuxarm-keyring` (137 paquetes, 116 MB bajados, ~680 MB instalados).
2. Instala el APK y pasa el tar por `adb` directo a `run-as tar` (sin copia temporal) → `files/archlinux`.
3. `scripts/arch-inicio.sh` (dentro de la app): agrega el usuario de la app a `/etc/passwd`, corre los `post_install` de los paquetes y `pacman-key --init` + `--populate archlinuxarm`.

Usar pacman: `GLIBC_FAKEROOT=1 pacman -S <paquete>` (ver `scripts/test-pacman.sh`).

`pacman.conf`:
- `IgnorePkg = glibc` y `NoExtract` de las bibliotecas de la glibc propia: pacman no la reemplaza por la de Arch.
- Sin `CheckSpace`: miraría los puntos de montaje de Android.
- Sin `DownloadUser`: no hay setuid.
- `DisableSandbox`: landlock no está permitido.
- `/usr/bin/ldconfig` es un script que no hace nada (en `NoExtract`): el de Arch es estático y esta glibc no usa `ld.so.cache`.

Parche `glibc/parches/0003-android-pacman.patch`:
- **Modo fakeroot** (`GLIBC_FAKEROOT=1`): `getuid`/`geteuid`/`getgid`/`getegid`/`getresuid`/`getresgid` devuelven 0, y `fchown`/`fchownat` dan por bueno el EPERM. Reemplaza al `fakeroot` de Arch, que usa SysV IPC (Android no lo tiene). Esas funciones pasan a C para que usen el gancho.
- `chroot` a la raíz virtual (`/`) es un no-op (pacman lo hace antes de los scriptlets); otros chroot siguen dando EPERM.
- **Enlaces duros**: si `linkat` falla con EACCES/EPERM, copia el archivo (o el enlace simbólico).
- **SIGSYS → ENOSYS**: libc instala en cada proceso (`__libc_early_init`) un manejador de SIGSYS. Si viene de seccomp, la syscall devuelve `-ENOSYS` y el programa sigue, como en un kernel sin esa syscall. `GLIBC_DEBUG_SIGSYS=1` anota cuáles en stderr. Así se encontraron:
  - `faccessat2` (439): la usaba cada `access()`; mataba a pacman. Sin flags → `faccessat`; con flags → ENOSYS directo (glibc usa su alternativa).
  - `fchmodat2` (452): ENOSYS directo (glibc usa `fchmodat`).
  - `accept` (202): bionic solo usa `accept4`. `gpg-agent` quedaba en un bucle infinito. Ahora `accept` → `accept4(..., 0)` en `__internal_syscall_cancel` (sigue siendo punto de cancelación).
- El rastreador ptrace (`tracer/`) no veía esos SIGSYS: bajo ptrace no se reproducían. El manejador es más confiable para diagnosticar.

Límites nuevos:
- **Binarios estáticos** (en `base` solo `ldconfig` y `sln`, static-pie) no se pueden ejecutar: no tienen intérprete y W^X bloquea `execve` desde los datos. Posible solución futura: que `execve` los cargue en espacio de usuario (mapear segmentos con `mmap`, armar la pila y saltar al punto de entrada).
- Los `post_install` que llaman a systemd (`systemctl`, audit) fallan sin consecuencias.
- DNS: `/etc/resolv.conf` fijo con 1.1.1.1 y 8.8.8.8; falta tomar el DNS de Android desde la app.
- No se re-ejecutó el bootstrap completo desde cero después de los últimos arreglos (`ldconfig`, `NoExtract`): se aplicaron en el prefijo del teléfono a mano y el bootstrap ya los incluye.

## Arquitectura propuesta

Una app ("contenedor" de Linux) con:

1. **Cargador en `nativeLibraryDir`** (`libld.so`), la única carpeta ejecutable de la app. Todo se arranca a través de él.
2. **Prefijo** en `files/` con el árbol de Arch (`usr/`, `etc/`, `var/`, `home/`...).
3. **glibc propia** (basada en la de Arch, mismo ABI para que los paquetes funcionen sin recompilar) con parches:
   - No llamar `set_robust_list` ni `rseq` (o tratar SIGSYS como ENOSYS).
   - **Traducción de rutas** dentro de glibc: `open`, `stat`, `access`, `readlink`, `opendir`, `exec*`, etc. redirigen `/usr`, `/etc`, `/lib`, `/var`, `/tmp`... al prefijo. Al estar en la propia libc es nativo, sin ptrace. (Los programas Go/estáticos que hacen syscalls directo no pasan por aquí.)
   - **`execve`** relanza siempre vía el cargador (`libld.so --library-path ... programa`), así los hijos funcionan sin `patchelf` y sin chocar con W^X.
   - `/dev/shm` → carpeta propia o `memfd`.
   - El cargador busca bibliotecas en el prefijo.
4. **Gestor de paquetes**: baja paquetes de Arch Linux ARM, resuelve dependencias, los extrae al prefijo convirtiendo enlaces duros en copias, y corre lo necesario de los hooks.
5. **Servicios**: supervisor simple (runit/s6) + servicio en primer plano de Android para que no lo maten.
6. **Gráficos**:
   - **Mesa Turnip** (soporta Adreno 619) compilado contra la glibc, usando `/dev/kgsl-3d0` → Vulkan; OpenGL vía Zink.
   - **Compositor Wayland dentro de la app** (wlroots o Smithay) que dibuja en superficies Android.
   - Meta: cada ventana Linux = una ventana/actividad Android independiente → aparece en recientes, pantalla dividida, flotante y en Mosaico.

Antecedente útil para ver qué parches hacen falta: el proyecto **glibc-packages** de la comunidad Termux (glibc nativa en Android con prefijo propio, sin traducción de rutas).

## Próximos pasos

1. **Compilar glibc propia** (cross-compile a aarch64 desde el PC, Arch Linux x86_64):
   - Partir del PKGBUILD de glibc de Arch Linux ARM (misma versión 2.43) para mantener ABI.
   - ✅ Primer parche mínimo: quitar `set_robust_list`/`rseq` → corre sin el rastreador.
   - ✅ Traducción de rutas y `execve` vía cargador.
2. ✅ Gestor de paquetes: pacman real (bootstrap desde el PC + pacman dentro de la app).
3. ✅ Terminal dentro de la app (ver "Para retomar"), con DNS de Android en `/etc/resolv.conf` y servicio en primer plano.
4. Binarios estáticos/static-pie: cargarlos en espacio de usuario desde `execve` (mapear segmentos, armar pila y auxv, saltar al punto de entrada).
5. ✅ Compositor Wayland (anfitrión propio + sway anidado, ver "Para retomar"). Siguiente: Turnip + `vkcube`, cuadros por GPU (dmabuf/AHardwareBuffer), mejoras de entrada.
6. Integración con Mosaico.

## Archivos

| Ruta | Qué es |
|---|---|
| `app/` | App de prueba (Java). `MainActivity` ejecuta `files/test.sh` y loguea con tag `GLIBC`; `TerminalActivity`/`TerminalService`: la terminal (log con tag `TERMINAL`). Variantes `sdk28`/`sdk36` |
| `app/src/main/jniLibs/arm64-v8a/libld.so` | Cargador `ld-linux-aarch64.so.1` de Arch (glibc 2.43) |
| `app/src/main/jniLibs/arm64-v8a/libtracer.so` | Rastreador compilado con NDK r28c (`aarch64-linux-android31-clang`) |
| `tracer/tracer.c` | Rastreador ptrace: sigue hijos, convierte SIGSYS de seccomp en `-ENOSYS` y anota la syscall |
| `scripts/preparar.sh` | Baja Arch ARM, arma el rootfs, parchea binarios y lo instala en las dos apps |
| `scripts/correr.sh` | `scripts/correr.sh sdk36 scripts/test-bateria.sh` → corre un test en la app y muestra la salida |
| `scripts/test-bateria.sh` | Batería: cargador desde `nativeLibraryDir`, con/sin rastreador, fork/hilos/señales/archivos |
| `scripts/test-rseq.sh` | Comprueba `GLIBC_TUNABLES=glibc.pthread.rseq=0` |
| `scripts/test-glibc-propia.sh` | Batería con la glibc propia, sin rastreador |
| `glibc/compilar.sh`, `glibc/Dockerfile` | Compila la glibc parchada (Docker); fuente en `glibc/glibc-2.43/`, objetos en `glibc/build/` |
| `glibc/parches/` | Parches sobre glibc 2.43: `0001` seccomp, `0002` rutas/execve, `0003` fakeroot/SIGSYS/enlaces duros, `0004` termios (`TCGETS2`→`TCGETS`), `0005` SIGSYS protegido de `sigaction`/máscaras, `0006` /proc sintético (stat, uptime, loadavg, version), `0007` `/proc/self/exe` = el programa, no el cargador |
| `scripts/bootstrap.py` | Arma el tar del prefijo Arch con pacman (resuelve dependencias, base de datos local) |
| `scripts/instalar-arch.sh` | Bootstrap + instala en la app (`files/archlinux`) + primer arranque |
| `scripts/arch-inicio.sh` | Primer arranque dentro de la app: usuario, `post_install`, llavero |
| `scripts/test-pacman.sh` | `pacman -Sy` + instalar nano/htop/git |
| `trabajo/` | Tar generado por el bootstrap (se puede borrar) |
| `glibc/verificar.sh` | Lista syscalls con rutas que no pasan por el traductor (desensamblado) |
| `scripts/instalar-glibc.sh` | Instala la glibc propia en la app de prueba (APK con `libldp.so` + prefijo `files/arch`) |
| `scripts/test-rutas.sh` | Batería de traducción de rutas/execve |
| `app/src/main/jniLibs/arm64-v8a/libldp.so` | Cargador de la glibc propia |
| `wayland/compilar.sh` | libffi + libwayland-server para Android (NDK) y xdg-shell; salida en `wayland/salida/` (requisito del build de la app) |
| `app/src/main/cpp/anfitrion.c` | Anfitrión Wayland (JNI); `Wayland.java` / `WaylandActivity.java` del lado Java |
| `app/src/main/java/.../Portapapeles.java` | Puente de portapapeles Android ↔ sway (wl-paste --watch / wl-copy) |
| `turnip/compilar-mesa.sh` | Compila Mesa/Turnip (KGSL) dentro del Arch de la app (copiar a `~/`) |
| `wayland/generar-teclado.sh` | Genera `Distribucion.java` (tabla de teclado) y `app/src/main/cpp/keymap.h` (keymap xkb para el anfitrión) con xkbcommon del PC |
| `turnip/egl-zink.c` | LD_PRELOAD para OpenGL por Zink en Wayland sin dmabuf (ver "GPU") |
| `scripts/correr-wl.sh` | Como `correr.sh` pero con el anfitrión Wayland corriendo (abre el escritorio, corre el script, captura). Para probar clientes Wayland por ADB |
| `scripts/test-cpu-dmabuf.sh` | CPU del anfitrión y de vkcube: dmabuf contra `MESA_VK_WSI_DEBUG=sw` |
| `turnip/prueba-dmabuf.c` | Prueba: memoria Vulkan exportable → dmabuf → mmap (compilar en la app con `-lvulkan`, necesita `vulkan-headers`) |
| `wlroots/compilar-wlroots.sh`, `wlroots/parches/` | wlroots 0.20.2 parchado (Vulkan sin DRM, allocator `android-ahb-v1`, linux-dmabuf sin DRM); se compila en el teléfono, sway lo usa con `LD_LIBRARY_PATH` (ver "Escritorio por GPU") |
| `scripts/subir-wlroots.sh`, `scripts/test-compilar-wlroots.sh` | Copian script, tarball y parches de wlroots a la app y lo compilan |
| `swayfx/compilar-swayfx.sh`, `scripts/subir-swayfx.sh`, `scripts/test-compilar-swayfx.sh` | swayfx 0.6 compilado en el teléfono (`~/swayfx`) |
| `sway/`, `scripts/subir-sway.sh`, `scripts/test-sway-config.sh` | Config de sway estilo HyDE (atajos, aspecto, waybar, fuzzel, kitty, bus D-Bus) y su instalación |
| `scripts/test-medir-wm.sh` | RAM y CPU de sway / swayfx / Hyprland anidados |
| `scripts/test-sway-vulkan.sh`, `scripts/test-cpu-sway.sh` | sway por GPU con foot y vkcube; CPU pixman contra GPU |

`instalar-glibc.sh sdk36 archlinux` actualiza solo la glibc (APK + bibliotecas del prefijo) tras recompilar.

Compilar e instalar: `./gradlew assembleDebug && adb install -r app/build/outputs/apk/sdk36/debug/app-sdk36-debug.apk` (ídem `sdk28`). Herramientas: Android SDK en `~/Android/Sdk`, NDK `28.2.13676358`; `patchelf` no está instalado en el sistema (`preparar.sh` lo baja).

Estado en el teléfono: instaladas las 2 apps de prueba (con el rootfs en su `files/`) y `/data/local/tmp/glibc` (rootfs de las pruebas como `shell`). En la sdk36: `files/archlinux` (Arch con pacman, ~800 MB), `files/arch`, `files/glibc`, `files/glibcp` (pruebas anteriores). Desinstalar la app borra todo. Limpiar:
```
adb uninstall dev.ben4shot.glibcprueba.sdk28
adb uninstall dev.ben4shot.glibcprueba.sdk36
adb shell rm -rf /data/local/tmp/glibc
```

## Preferencias de trabajo

- Conversación en español.
- Antes de un comando ADB largo, decir en una línea qué hace y si es solo lectura o modifica algo. Nunca borrar datos de apps sin confirmación.
- Hablar de lo que es técnicamente posible; no gastar tiempo revisando políticas de HyperOS o licencias.
- Todo reversible, sin poner en riesgo las apps bancarias.
