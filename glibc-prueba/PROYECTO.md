# Linux real en Android, sin root

Documento de contexto del proyecto. Resume la idea, las decisiones tomadas (y por qué), lo que ya se probó en el teléfono y lo que sigue. Escrito el 2026-10-19 (primera sesión) y actualizado al cerrar la segunda (terminal, Wayland, GPU).

## Objetivo principal

Que el teléfono (Redmi 15 5G, HyperOS, **sin root**) sea a la vez Android y un **Linux real y totalmente modificable**: programas de Arch Linux ARM sin recompilar corriendo nativos (glibc propia dentro de una app normal, sin proot ni emulación), con un **escritorio Wayland mínimo y modificable, tipo Hyprland adaptado al celular**, y **aceleración por GPU** (Turnip en la Adreno 619). Sin perder lo de Android que importa (apps bancarias chilenas, Play Store, cámara, pagos) y todo reversible: es una app, se desinstala y el teléfono queda igual. Más adelante: integrarlo con Mosaico (cada ventana Linux como ventana Android) y, si se puede, Steam.

## Para retomar (estado al 2026-10-19, fin de la segunda sesión)

| Frente | Estado |
|---|---|
| glibc propia + pacman de Arch ARM | ✅ (parches `0001`–`0006`) |
| Terminal en la app ("Terminal Arch") | ✅ bash interactivo, htop, nano, `sudo pacman` |
| Wayland ("Wayland Arch") | ✅ anfitrión propio + sway 1.12 anidado + foot; tacto, scroll, teclado latam |
| GPU | ✅ Vulkan: Turnip (KGSL) compilado en el teléfono, `vkcube` en la Adreno 619. Sin OpenGL todavía |

**Cómo se usa hoy:**
1. "Terminal Arch" → bash de Arch. Paquetes: `sudo pacman -S <paquete>` (`sudo` = modo fakeroot de la glibc).
2. Escritorio: en la terminal `sway &`, abrir "Wayland Arch", tocar SUPER y luego Enter → foot. Fila de abajo: ⌨ (teclado Android), ESC, TAB, CTRL/ALT/SUPER (valen para la tecla siguiente), flechas.
3. Vulkan: desde una foot de sway, `vkcube` (la terminal ya exporta `VK_ICD_FILENAMES` y `MESA_VK_WSI_DEBUG=sw`).

**Probar a mano (no se pudo por ADB):** teclado físico (US) en "Wayland Arch", scroll con dos dedos, clic derecho (mantener), ñ/tildes desde Gboard, nano/htop a pantalla completa, girar la pantalla.

**Pendientes, en el orden sugerido:**
1. **Zink** (OpenGL sobre Turnip): recompilar Mesa con `-Dgallium-drivers=zink` + EGL/GL. Ojo: EGL en Wayland normalmente exige dmabuf; ver si Zink/kopper puede presentar por `wl_shm` como el WSI `sw` de Vulkan.
2. **Evitar la copia por CPU**: el anfitrión reserva `AHardwareBuffer` (gralloc = dmabuf), pasa el fd con `AHardwareBuffer_sendHandleToUnixSocket`, Turnip lo importa por KGSL; el anfitrión implementa `linux-dmabuf` y muestra el buffer sin copiar (o al menos sin pasar por shm).
3. **Escritorio por GPU**: los renderers de wlroots (GLES2/Vulkan) buscan un nodo DRM que no existe → adaptar (p. ej. renderer Vulkan de wlroots con Turnip sin DRM). Requisito para Hyprland, que no tiene renderer por CPU.
4. **Escritorio cómodo en el celular**: config de sway propia (gestos para escritorios, barra útil, cursor más grande, lanzador `wmenu`/`fuzzel`); popups xdg (hoy se cierran: menús GTK/Qt no andan); portapapeles Android ↔ Wayland; `wl_subcompositor`; keymap real para clientes conectados directo al anfitrión.
5. **Xwayland** (apps X11; Steam lo necesita).
6. **Steam**: revisar el cliente oficial para ARM que menciona el usuario; si no sirve, FEX-Emu (ver abajo).
7. Binarios estáticos (cargarlos en espacio de usuario desde `execve`).
8. Integración con Mosaico: cada ventana Linux = ventana Android (recientes, dividida, flotante). El usuario anotó que más adelante se puede saltar el `SurfaceView`.
9. Menores: `/dev/shm` es carpeta en disco (¿memfd?); re-ejecutar `instalar-arch.sh` desde cero para validar el bootstrap con todos los arreglos.

### Detalle por frente

**glibc + pacman:** glibc 2.43 propia (parches en `glibc/parches/`) que corre binarios de Arch Linux ARM sin recompilar dentro de una app normal: traducción de rutas (`GLIBC_PREFIX`), `execve` vía el cargador `libldp.so`, scripts `#!`, modo `GLIBC_FAKEROOT`, SIGSYS → ENOSYS. **pacman real funciona dentro de la app** (sincroniza, verifica firmas, instala con dependencias). Detalle en las secciones de abajo.

**Terminal dentro de la app (2026-10-19, funciona):** `TerminalActivity` (lanzador "Terminal Arch") + `TerminalService` (primer plano, dueño de la sesión). Usa la vista de Termux (`com.github.termux.termux-app:terminal-view:v0.118.3` de JitPack: solo el emulador y `libtermux.so`, que abre el pty) y lanza `libldp.so /usr/bin/bash -l` en `files/archlinux` con `HOME=/home/user`, `PATH=/usr/local/bin:/usr/bin`, `TERM=xterm-256color`. Al abrir escribe `/etc/resolv.conf` con el DNS de Android (+1.1.1.1) y crea `/usr/local/bin/sudo` = `GLIBC_FAKEROOT=1 exec "$@"` (para `sudo pacman ...`). Fila de teclas extra (ESC, TAB, CTRL, ALT, flechas); pellizcar cambia el tamaño de letra; Enter con la sesión terminada cierra todo. `MainActivity` sigue para `correr.sh` (ya no es lanzador).
- **Parche `0004` (termios)**: glibc ≥ 2.42 usa `TCGETS2`/`TCSETS2`, que SELinux no deja usar a las apps sobre `devpts` → `isatty` daba 0 y bash no era interactivo (sin prompt, nano "not a terminal"). Ahora reintenta con `TCGETS`/`TCSETS`. Verificado con `script` dentro de la app: `bash -i` interactivo, `tty`, `stty`.
- **Parche `0005` (SIGSYS protegido)**: bash interactivo instala manejadores para todas las señales fatales, SIGSYS incluida → reemplazaba el de libc y la primera syscall bloqueada por seccomp (`faccessat2` del `test -r` de `/etc/profile`) lo mataba (señal 31). Ahora `sigaction(SIGSYS)` del programa se guarda aparte (recibe solo los SIGSYS que no son de seccomp, ej. `kill -SYS`), y SIGSYS nunca se bloquea (`clear_internal_signals`, también se quita del `sa_mask`): con la señal bloqueada el kernel la forzaría con SIG_DFL.
- **Parche `0006` (/proc sintético)**: SELinux no deja a las apps leer `/proc/stat`, `uptime`, `loadavg`, `version`, `vmstat`, `diskstats` (htop: "Cannot open /proc/stat"). Si `openat` de `/proc/{stat,uptime,loadavg,version}` en lectura da `EACCES`, libc arma el contenido en un `memfd`: inactivo por CPU desde `/sys/devices/system/cpu/cpuN/cpuidle/state*/time` (legible), ocupado = tiempo desde el arranque (`CLOCK_BOOTTIME`) − inactivo (todo como `user`), `btime`, carga de `sysinfo()`, versión de `uname()`. Probado: htop, `uptime`, `ps`. Las apps solo ven sus propios procesos en `/proc` (no tiene arreglo sin root). La terminal pasa `TZ` con la zona de Android.
- Probado en pantalla: prompt `[user@localhost ~]$`, `stty size` = tamaño de la vista, `resolv.conf` con el DNS de la red. Falta: nano/htop a pantalla completa en el teléfono, girar, `sudo pacman -S`. `which` no viene en el Arch mínimo.

**Wayland (2026-10-19, funciona): anfitrión propio + sway anidado.** sway 1.12 / wlroots 0.20.2 / foot de Arch corren tal cual y se ven en la app.
- `wayland/compilar.sh`: libffi 3.5.2 + libwayland-server 1.26.0 estáticas para Android (NDK, meson cruzado) y código de servidor de xdg-shell (`wayland-scanner` del PC) en `wayland/salida/`.
- `app/src/main/cpp/anfitrion.c` (`libanfitrion.so`, CMake desde Gradle): compositor mínimo en bionic con `wl_compositor` v6, `wl_shm` (+XBGR/ABGR), `xdg_wm_base` v2, `wl_seat` v7, `wl_output` v4. Muestra a pantalla completa el último `xdg_toplevel` mapeado: copia el buffer shm (XRGB→RGBX) a la `ANativeWindow` del `SurfaceView` y guarda el último cuadro para redibujar. Tacto = puntero (botón izquierdo). Teclado = códigos evdev sin keymap (`NO_KEYMAP`: el backend wayland de wlroots ignora el keymap del anfitrión y usa el de la config de sway). Hilo propio con `wl_display_run`; Java → cola + `eventfd`.
- Socket `wayland-0` en `<prefijo>/run/user/<uid>` (dentro: `XDG_RUNTIME_DIR=/run/user/<uid>`). Lo arranca la terminal (`Wayland.iniciar`) y `WaylandActivity` (lanzador "Wayland Arch": `SurfaceView` + fila ⌨ ESC TAB CTRL ALT SUPER flechas; mapa de teclas Android → evdev, distribución US).
- La terminal exporta `XDG_RUNTIME_DIR`, `WAYLAND_DISPLAY=wayland-0`, `WLR_RENDERER=pixman` y crea `<prefijo>/dev/shm` (`shm_open` de glibc → wlroots fallaba con "Failed to allocate shm file"). `~/.config/sway/config` = `include /etc/sway/config` + `output * scale 2.5`.
- Uso: en la terminal `sway &` (o `sway 2>/tmp/sway.log &`), abrir "Wayland Arch", SUPER y Enter → foot.
- **Entrada** (`WaylandActivity`): toque = clic izquierdo, arrastrar = clic sostenido, mantener 450 ms = clic derecho, dos dedos = scroll (`wl_pointer.axis`, fuente finger, `axis_stop` al soltar). Cursor dibujado por sway (`WLR_NO_HARDWARE_CURSORS=1`; el anfitrión ignora `set_cursor`).
- **Teclado latam**: sway con `xkb_layout latam`; `Distribucion.java` (carácter → evdev + Shift/AltGr) la genera `wayland/generar-teclado.sh` con xkbcommon desde el keymap real (otra distribución: regenerar y cambiar la config de sway). Tildes/diéresis: NFD → tecla muerta + letra; `^` `` ` `` sueltos: tecla muerta + espacio. AltGr = `KEY_RIGHTALT` → Mod5. De teclados virtuales se ignoran los modificadores sueltos (adb/Gboard mandan Shift aparte y se sumaba al de la tabla); Ctrl/Alt se toman del meta state. Teclado físico (el del usuario es US): las teclas con carácter se traducen con la distribución que Android tenga para ese teclado y se pasan a latam con la tabla (el Shift físico se suelta/restaura según pida la tabla); modificadores y teclas sin carácter van crudas por scancode; Alt derecho → Alt (en US no es AltGr). Sin probar todavía con el teclado real. El teclado de Android puede estar en cualquier idioma.
- Probado: símbolos `@#{}[]=*/\|~<>?!^`` ` ``, CTRL+C desde la fila, clic para cambiar foco entre dos foot. Falta probar a mano: scroll con dos dedos, clic derecho, ñ/tildes desde Gboard.
- Limitaciones: popups se cierran al pedirse, sin portapapeles, render por CPU (pixman + copia), sin Xwayland/swaybg, cursor chico. `/dev/shm` es una carpeta en disco (los archivos se borran al crearse; ver si conviene memfd).
- Config de sway en el teléfono (`~/.config/sway/config`): `include /etc/sway/config`, `output * scale 2.5`, `input type:keyboard xkb_layout latam`.

**GPU (2026-10-19, funciona): Turnip + KGSL.** `/dev/kgsl-3d0` abre rw desde la app; `/dev/dma_heap/*` y `/dev/dri` no (SELinux) → sin dmabuf por ahora.
- Mesa 26.2.5 (misma versión que Arch ARM) compilada **en el teléfono**, dentro del Arch de la app (gcc 16.1.1, meson, ninja; 725 pasos en 6 min): `turnip/compilar-mesa.sh` → `~/compilar-mesa.sh`, se corre desde la terminal (servicio en primer plano: Android no congela el proceso) con `bash ~/compilar-mesa.sh > ~/mesa.log 2>&1 &`. Fuente en `~/src/mesa-26.2.5.tar.xz` (se baja en el PC y se copia). Solo Vulkan freedreno, `-Dfreedreno-kmds=kgsl -Dplatforms=wayland`, sin GL/gallium/LLVM. Instalado en `~/turnip`. Dependencias de compilación instaladas con pacman: gcc make meson ninja pkgconf bison flex python-mako python-yaml python-packaging libdrm wayland-protocols glslang vulkan-tools.
- `vulkaninfo`: `Turnip Adreno (TM) 619`, Vulkan 1.3, Mesa 26.2.5. `vkcube` se ve dentro de sway: render en la GPU y presentación por `wl_shm` (`MESA_VK_WSI_DEBUG=sw`: Mesa copia el cuadro a memoria compartida; sin dmabuf no hay otra).
- La terminal exporta `VK_ICD_FILENAMES` (Turnip) y `MESA_VK_WSI_DEBUG=sw`.
- Siguiente: Zink (OpenGL sobre Turnip) para apps GL; evitar la copia (AHardwareBuffer: `AHardwareBuffer_sendHandleToUnixSocket` da el dmabuf de gralloc, que KGSL puede importar); sway/Hyprland por GPU necesitan EGL/GBM o el renderer Vulkan de wlroots, que buscan un nodo DRM (no hay) → habría que adaptarlos.

**Steam (idea, sin empezar):** no hay multilib en ARM (multilib = libs i686 del Arch x86_64) y Steam es solo x86. Camino: FEX-Emu (emulador x86/x86_64 con JIT, en espacio de usuario; lo que usa Valve en ARM) + rootfs x86_64 con Steam. El teléfono es solo 64 bits (`ro.product.cpu.abilist32` vacío) → box86 descartado. El usuario dice que ya hay cliente oficial de Steam para ARM (a revisar). Requisitos antes: Xwayland, GPU (Turnip; FEX pasa GL/Vulkan al Mesa nativo con thunks). Ojo: FEX hace las syscalls del invitado directo (no pasan por el traductor de rutas de la glibc), usa su propio RootFS. Repos de Arch ARM: core, extra, alarm, aur (no hay fex/box64; sí qemu-user).

**Comandos:**
- Repo git en `..` (raíz `Android/`): fuera del repo quedan los generados (árbol `glibc/glibc-2.43/`, `glibc/build`, `glibc/salida`, `wayland/{fuentes,build,salida}`, `trabajo/`); todo se reconstruye con los scripts.
- Compilar la app: primero `wayland/compilar.sh` (una vez; bibliotecas Wayland para el anfitrión), luego `./gradlew assembleSdk36Debug && adb install -r app/build/outputs/apk/sdk36/debug/app-sdk36-debug.apk`. Reinstalar cierra la terminal, sway y todo lo que corra en la app.
- Tabla de teclado: `wayland/generar-teclado.sh [distribución]` (y cambiar `xkb_layout` en la config de sway).
- Turnip: `turnip/compilar-mesa.sh` se copia a `~/` del Arch de la app junto con `~/src/mesa-26.2.5.tar.xz` y se corre desde la terminal (ver "GPU").
- Recompilar glibc: `glibc/compilar.sh` (Docker; incremental; baja el tarball y aplica los parches si falta el árbol). **Si se agregan archivos `.c` nuevos a sysdeps, borrar `glibc/build/` antes** (la lista de stubs de syscalls se genera una vez).
- Verificar que ninguna syscall con rutas se escape del traductor: `glibc/verificar.sh`.
- Instalar la glibc nueva en el teléfono: `scripts/instalar-glibc.sh sdk36 archlinux` (APK con `libldp.so` + bibliotecas en el prefijo).
- Correr algo dentro de la app: `TIEMPO=<segundos> scripts/correr.sh sdk36 <script.sh>` (ej. `scripts/test-pacman.sh`, `scripts/test-rutas.sh`).
- Editar los parches: el árbol `glibc/glibc-2.43/` ya tiene los 6 aplicados. Para guardar cambios nuevos, generar `0007-...patch` con `diff -u --label a/F --label b/F` contra un árbol tarball + parches 0001–0006 (ojo: `diff -rq` sale en español, usar `LC_ALL=C` para listar archivos), y comprobar que los parches reproducen el árbol exacto (así se hizo con 0002 y 0003).

**Tropiezos (para no repetir):**
- En los scripts que corre la app, **no exportar `PATH=/usr/bin`** para el `sh` de Android: rompe `mkdir`, `id`, `grep`… Ponerlo solo delante del comando glibc (`PATH=/usr/bin $L /usr/bin/bash -c '...'`).
- `correr.sh` deja de esperar cuando ve `=== fin` **o la palabra `error`** en la salida; para procesos largos subir `TIEMPO`.
- El rastreador ptrace no veía los SIGSYS de `faccessat2`/`accept`: para diagnosticar usar `GLIBC_DEBUG_SIGSYS=1`.
- Un proceso colgado de la app se ve con `adb shell "ps -A -o PID,STAT,TIME,ARGS -u u0_a294"` y se detiene con `adb shell "run-as dev.ben4shot.glibcprueba.sdk36 kill <pid>"` (el `/proc/<pid>` de la app no se puede leer por ADB).
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
| `glibc/parches/` | Parches sobre glibc 2.43: `0001` seccomp, `0002` rutas/execve, `0003` fakeroot/SIGSYS/enlaces duros, `0004` termios (`TCGETS2`→`TCGETS`), `0005` SIGSYS protegido de `sigaction`/máscaras, `0006` /proc sintético (stat, uptime, loadavg, version) |
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
| `turnip/compilar-mesa.sh` | Compila Mesa/Turnip (KGSL) dentro del Arch de la app (copiar a `~/`) |
| `wayland/generar-teclado.sh` | Genera `Distribucion.java` (tabla de teclado) con xkbcommon del PC |

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
