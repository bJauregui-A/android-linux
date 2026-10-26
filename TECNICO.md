# Linux real en Android, sin root: documentación técnica

Una app de Android (`dev.ben4shot.glibcprueba.sdk36`) que corre **Arch Linux ARM y Debian ARM64 sin recompilar**, de forma nativa: usa una glibc propia parchada, sin root, sin proot y sin Termux, y tiene escritorios Wayland/X11 por GPU (Turnip en la Adreno). Lo de Android que importa (apps bancarias, Play Store, pagos) sigue funcionando y todo es reversible: al desinstalar la app, el teléfono queda como estaba.

Para una introducción corta (qué es, red y reenvío de puertos), ver [`README.md`](README.md). Lo pendiente está en [`backlog.md`](backlog.md). La historia de cada cambio está en `git log`.

## Teléfono

| | |
|---|---|
| Modelo | Redmi 15 5G (`spring`, región CL), HyperOS 3 / Android 16 (SDK 36) |
| SoC / GPU | Snapdragon 6s Gen 3 (SM6375) / Adreno 619 (`/dev/kgsl-3d0`). Núcleos 0–5 lentos, 6–7 rápidos |
| Kernel | GKI 6.1, sin `/dev/kvm` |
| Bootloader | **bloqueado**, a propósito (Play Integrity de los bancos) |

También se probó en un Xiaomi 12T Pro y en una Lenovo Tab P11 (Android 11: sin `ASurfaceControl`, copia por CPU). La tablet es prestada: no se trabaja en ella salvo que se pida.

## Límites duros sin root

Sin namespaces (Docker, Flatpak, bwrap, sandbox de Chromium → `--no-sandbox`), sin systemd como PID 1 ni `systemd --user`, sin cgroups, sin módulos ni KVM, sin FUSE (portal de documentos), sin DRM/KMS ni logind. No se pueden ver los procesos ni los archivos de otras apps, y no hay `/dev/input` ni `uinput`. Android no deja crear enlaces duros, y W^X impide `execve` desde la carpeta de datos.

## Cómo funciona

```
Android (bionic)                           Linux (glibc propia)
SistemaActivity ── elige/crea instancias    files/instancias/<id>/  (usr, etc, home...)
TerminalService ── sesiones, puentes ─────▶ libldp.so (cargador, en nativeLibraryDir)
WaylandActivity ── anfitrión Wayland            └─ libc.so.6 parchada: rutas, seccomp, usuarios...
  (anfitrion.c, wayland-0)  ◀──────────────  sesion-android → compositor del escritorio elegido
Audio/Portapapeles/Notificar/Abrir/Mandos ◀─ autostart-android (D-Bus, PipeWire, sshd, ...)
```

- **Cargador en `nativeLibraryDir`** (`jniLibs/arm64-v8a/libldp.so`): es la única carpeta de la app que Android deja ejecutar. Todo programa Linux arranca a través de él, y la glibc reescribe cada `execve` para que pase de nuevo por el cargador.
- **Instancias**: cada una es un rootfs propio en `files/instancias/<id>` (Arch o Debian), con su IP virtual y sus sesiones. El registro está en `SistemaLinux.java` (shared prefs `instancias_json`). Los adaptadores son `AdaptadorArchArm64` y `AdaptadorDebianArm64`.
- **APK autoinstalable**: `apk/armar.sh` genera `base.tgz` (Arch: pacman + dependencias, `scripts/bootstrap.py`), `base-debian.tgz` (`scripts/bootstrap-debian.py`) y `capa.tgz` (lo compilado en el teléfono + configs + instalador, `apk/capa.py`). Al crear una instancia, `apk/instalar.sh` (sh de Android) extrae todo y `apk/primer-arranque.sh` (bash) corre el asistente: usuario, contraseña, escritorio, módulos y `sudo` real.
- **Escritorios** (`glibc-prueba/escritorios/`): cada carpeta tiene `escritorio.conf` (`NOMBRE`, `DESCRIPCION`, `ESTADO` probado|sin-probar, `PROVEEDOR_PANTALLA`, `REQUISITOS_SESION`, `CAPACIDADES_REQUERIDAS`, `READY_LEVEL`), `paquetes.txt`, `sesion` (termina con `exec` del compositor) y `home/` (configuración inicial; `@ESCALA@`). El orden del menú está en `escritorios/orden`. Hay tres proveedores en `escritorios/proveedores/`: `wayland-anidado` (se conecta a `wayland-0` del anfitrión), `x11-directo` (`DISPLAY=:0`) y `ninguno` (consola). `sesion-android` valida, lanza y espera *readiness*, publica `linux-session.properties` y arranca `autostart-android`. 14 escritorios Wayland: sway, hyprland, labwc, xfce, lxqt, kde, plasma-movil, phosh, niri, cosmic, wayfire, river, qtile y weston. Hay que lanzar KDE directo con `kwin_wayland --exit-with-session`: `startplasma` se cierra solo.
- **Servicios**: `glibc-prueba/supervisor/` es un demonio en C con su CLI, `service <acción> <nombre>` (alias `sv`). Lee unidades de systemd (`/etc/services.d`, `/usr/lib/systemd/system`, `/lib/systemd/system`) y entiende `ExecStartPre`, `EnvironmentFile` y alias.
- **Red virtual**: cada instancia tiene una IP fija de su subred (por defecto `sub_default`, `10.0.0.0/24`; la `.1` es el gateway) guardada en `RedManager` (`/etc/virtual-ip`, `vnet0`), que la glibc mapea a `127.0.0.N`. Al crear se asigna la primera libre, al borrar se libera, y al abrir la app se limpian las de instancias inexistentes y se completan las que faltan (`AsignacionIps`). Al abrir la app también se ofrece borrar las carpetas de `files/instancias/` sin instancia registrada (`CarpetasInstancias`), nunca si la lista de instancias no se pudo leer. El reenvío de puertos lo hace `RedManager.java`, y para los puertos < 1024 hay un proxy en el usuario `shell` (`android/proxy-*`).
- **GPU**: Turnip (Mesa compilada en el teléfono, sobre KGSL) da Vulkan, y Zink da OpenGL 4.6 / GLES 3.2. El camino sin copias usa el protocolo propio `wayland/android-ahb-v1.xml`, en el que el anfitrión entrega `AHardwareBuffer` y se presentan con `ASurfaceControl`, con parches a la WSI de Mesa (`turnip/parches/`) y a wlroots (`wlroots/parches/`: Vulkan sin DRM, allocator AHB). Para los compositores que exigen DRM/GBM, `turnip/udmabuf-shim.c` (`LD_PRELOAD`) emula `/dev/dri/renderD128` y `/dev/udmabuf` sobre `dma_heap`. `mesa-gl/` es un GL de Mesa propio: drisw lee el cuadro de Zink y lo copia a la ventana (X11 por SHM). Se usa con `con-gpu <programa>` y con el envoltorio de Firefox.
- **Integración con Android**: audio (PipeWire → FIFO → AudioTrack), portapapeles (`wl-paste`/`wl-copy`), notificaciones D-Bus → Android, `xdg-open` → intents, `/sdcard` completo (`MANAGE_EXTERNAL_STORAGE`) y mandos (evdev emulado por socket).

### Parches de glibc 2.43 (`glibc-prueba/glibc/parches/`)

| | |
|---|---|
| 0001–0007 | seccomp de apps (`set_robust_list`, `rseq`), traducción de rutas y `execve` por el cargador (`GLIBC_PREFIX`), fakeroot + SIGSYS→ENOSYS + enlaces duros como copias, termios (`TCGETS`), SIGSYS protegido, `/proc` sintético, `/proc/self/exe` |
| 0008–0014 | SysV IPC (sem, shm), relanzar `/proc/self/exe`, set\*id, `get_robust_list` y sockets Unix con ruta larga, `mprotect PROT_EXEC` → copia, evdev (mandos), `sigall_set` sin SIGSYS |
| 0015–0018 | capa seccomp propia (Go, `svc` y `syscall()` crudos se traducen), SIGSYS del filtro del propio programa, `/proc/bus/pci` vacío, manejador SIGSYS en pila propia (Go) |
| 0019–0024 | hostname, Netlink de rutas (`ip a/r/link/neigh`), audit netlink (PAM), red virtual, **binarios estáticos**, destraducir AF_UNIX |
| 0025 | raíz cerrada: `..` no sale de la instancia (`android-raiz.c`) |
| 0026–0028 | usuarios virtuales: credenciales por proceso (`GLIBC_CRED`), dueño virtual en el xattr `user.linux.owner`, `chown` persistente, cerrojo de shadow (`st_nlink = 2`), setuid virtual en `execve` (sudo real) |

## Repo

| Ruta | Qué es |
|---|---|
| `glibc-prueba/app/` | App Java + anfitrión Wayland en C (`src/main/cpp/anfitrion.c`). `src/debug/ReceptorPruebas.java`: correr pruebas desde el PC. Variante única `sdk36`; tipo `diagnostico` recorre los escritorios al abrir |
| `glibc-prueba/glibc/` | `compilar.sh` (Docker, salida en `glibc/salida/`), `parches/`, `verificar.sh` (syscalls con ruta que se escapan del traductor) |
| `glibc-prueba/apk/` | Armado del APK (`armar.sh`, `capa.py`, `traer-compilados.sh`), instalador (`instalar.sh`, `primer-arranque.sh`) y listas `paquetes-*.txt` (Arch; `-apt` = Debian) |
| `glibc-prueba/escritorios/` | Perfiles, proveedores, `sesion-android`, `autostart-android` |
| `glibc-prueba/supervisor/` | `service` / `service-daemon` (`compilar.sh` ARM64 o `--local` para el PC) |
| `glibc-prueba/wayland/` | libwayland para el NDK y protocolos (`compilar.sh`, requisito del build); `generar-teclado.sh` (tabla latam) |
| `glibc-prueba/turnip/`, `wlroots/`, `sway/`, `mesa-gl/` | Recetas y parches que se compilan **en el teléfono** (`~/turnip`, `~/wlroots`, `~/sway`, `~/mesa-gl`). `sway/` también tiene la config estilo HyDE |
| `glibc-prueba/android/` | Integración: `xdg-open`, notificaciones, proxy de puertos, limpieza de `/dev/shm` |
| `glibc-prueba/scripts/` | `bootstrap*.py`, `probar-en-telefono.sh`, `instalar-libc-en-instancia.sh`, `adb-conectar` |
| `glibc-prueba/pruebas/` | Pruebas (ver abajo) |
| `debloat/` | Debloat de HyperOS por ADB |

Generado, fuera del repo: `glibc/glibc-2.43/`, `glibc/build/`, `glibc/salida/`, `wayland/{fuentes,build,salida}/`, `trabajo/` (incluye `compilados.tar`, **única copia** de lo compilado en el teléfono).

## Compilar e instalar (desde el PC)

```sh
cd glibc-prueba
wayland/compilar.sh                 # una vez, o si cambian los protocolos
glibc/compilar.sh                   # glibc → glibc/salida (incremental)
apk/armar.sh                        # base.tgz, base-debian.tgz, capa.tgz → trabajo/assets-sdk36
cp glibc/salida/usr/lib/ld-linux-aarch64.so.1 app/src/main/jniLibs/arm64-v8a/libldp.so  # si cambió el cargador
./gradlew assembleSdk36Debug
adb install -r app/build/outputs/apk/sdk36/debug/app-sdk36-debug.apk   # conserva instancias, MATA la sesión
scripts/instalar-libc-en-instancia.sh <id>   # libc nueva en una instancia ya creada (respaldo y --revertir)
```

Toda glibc nueva va al APK (`libldp.so`, `base*.tgz`, `capa.tgz`) **y** a las instancias existentes. La capa solo se aplica al crear una instancia.

## Pruebas (TDD)

Flujo: `/backlog` (historias) → `/story <historia>` (genera `plan.md`) → `/pair` (rojo → verde → refactor, una prueba a la vez).

- **En el PC**: `./gradlew testSdk36DebugUnitTest` (JUnit en `app/src/test/`, lógica pura de IP y carpetas sueltas), `pruebas/raiz/test.sh` (resolvedor de rutas en C) y `supervisor/compilar.sh --local` con `SERVICE_ROOT=<rootfs falso>`.
- **Dentro de la app** (con el seccomp real): `scripts/probar-en-telefono.sh [--conservar] <instancia> <script> [límite]`. Sale con el código del script; el 3 significa que no llegó. Necesita un APK de depuración **y una sesión de la app abierta** (`adb shell am start -n dev.ben4shot.glibcprueba.sdk36/dev.ben4shot.glibcprueba.TerminalActivity`). `adb shell` y `run-as` **no** tienen el seccomp de la app: no sirven para probar syscalls.
- Suites: `pruebas/cred/test.sh`, `pruebas/dueno/dentro.sh`, `pruebas/suid/dentro.sh`, `pruebas/sudo/dentro.sh`, `pruebas/raiz/en-telefono.sh`, `pruebas/intent/autoprueba.sh` (con salidas de referencia en `salidas/`).

## Trampas conocidas

- `adb install -r`, `am force-stop`, reiniciar sway o instalar una libc en la instancia en uso **matan la sesión** (también al agente si corre dentro del teléfono).
- glibc: si se agregan `.c` nuevos a `sysdeps`, hay que borrar `glibc/build/` (o al menos `sysd-syscalls` y los `.o`). La lista de stubs se genera una sola vez.
- Debian no usa `ld.so.cache`: depende de `LD_LIBRARY_PATH`, que hay que pasar también a ssh (`SetEnv`) y a sudo (`env_keep`).
- sudo no puede abrir su propia pty dentro de la app (`unable to allocate pty`): la regla del instalador lleva `Defaults !use_pty`.
- El `tar` de la base no conserva setuid: `primer-arranque.sh` lo vuelve a poner (`sudo`, `su`, `passwd`...).
- Programas que no pasan por la glibc para `getuid` (Go, estáticos de otra libc) ven el UID real. `/proc/<pid>/status` también lo muestra.
- Los servicios de una instancia escuchan en su `127.0.0.N`, no en `127.0.0.1`.
- `/dev/shm` y SysV IPC son archivos en disco del prefijo (`/dev/shm/.sysv`), y pueden quedar huérfanos.
- Android reescribe la afinidad de CPU al cambiar la app de grupo (top-app/background). `sway/nucleos.py` la reajusta.
- Las capturas se sacan con `grim` dentro de sway, nunca con `screencap` con la app atrás (captura chats privados).
- `pkill -f <ruta>` no encuentra a `service-daemon` (`argv[0]` corto): hay que matarlo por PID.
- En los scripts que corre el `sh` de Android, no exportar `PATH=/usr/bin` (rompe sus herramientas).

## Debloat (`debloat/`)

Se quitaron 22 paquetes con `pm uninstall --user 0` (lista en `eliminados.txt`, respaldo en `backup-paquetes-2026-10-18.txt`). Para restaurarlos: `debloat/restaurar.sh` o `adb shell cmd package install-existing <paquete>`.
**No tocar**: `securitycenter`, `powerkeeper`, `joyose`, `xmsf`, `updater`, `gallery`, `mediaviewer`, `longcheertel.cit`, `qti`/`qualcomm`, `com.miui.home` (maneja recientes y gestos).
Ajustes hechos por ADB (reversibles): gestos de 3 dedos de HyperOS apagados (`settings put system enable_three_gesture 0`), monitor de procesos fantasma apagado (`settings put global settings_enable_monitor_phantom_procs false`), sin restricciones de batería para la app.
