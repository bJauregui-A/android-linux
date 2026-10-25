# B26 · Raíz cerrada (chroot emulado en la glibc)

Historia para la sesión de código. Escrita el 2026-10-25 desde `BACKLOG.md` (B26). Leer antes `AGENTS.md` (reglas de libc nueva, empaquetado y no matar la propia sesión).

## Historia

**Como** usuario de una instancia Linux en la app,
**quiero** que `/` sea la raíz de verdad de esa instancia, como en un PC,
**para que** `..` no me saque a la carpeta de la app ni a otras instancias, y los programas que recorren el sistema de archivos (`find /`, `realpath`, `du`, instaladores) vean un Linux normal.

## Problema (reproducido el 25-oct, capturas 05:24 y 05:25)

En la instancia `dev-6918` (Arch):

```
$ cd / ; ls ..        →  arch-arm64  dev-6918  dev-94692      (debería ser: bin boot dev etc ...)
$ ls /..              →  arch-arm64  dev-6918  dev-94692
$ python /../dev-6918/home/user/test.py   →  hola          (leyó un archivo de otra instancia)
```

`cd /..` parece funcionar solo porque bash normaliza `$PWD` por su cuenta; `cd -P /..` sale.

## Causa (código actual)

`glibc/glibc-2.43/sysdeps/unix/sysv/linux/aarch64/android-path.c`:

- `xlat()` (línea ~261) solo antepone `PREFIX` a las rutas absolutas: `/..` pasa a ser `PREFIX/..`, que es la carpeta padre (`files/instancias/`).
- Las rutas **relativas** no se tocan (`if (in[0] != '/') return in;`): el kernel resuelve `..` desde el cwd real y sube sin límite.
- Las `*at` con `dirfd` distinto de `AT_FDCWD` y ruta relativa con `..`, igual.
- `getcwd` ya quita el prefijo (`unxlat`), y `chroot` solo acepta `chroot("/")`.

## Hecho y descartado

- `openat2(..., RESOLVE_IN_ROOT)`: **descartado**. El seccomp de apps de Android bloquea `openat2` entero (ENOSYS con y sin `RESOLVE_IN_ROOT`; probado el 25-oct en `dev-6918`, `Seccomp: 2`). Todo se resuelve en la glibc.
- `chroot()` real: imposible sin root (`CAP_SYS_CHROOT`).

## Diseño

**Regla de oro:** las rutas **sin** ningún componente `..` siguen exactamente el camino de hoy (sin syscalls extra). Solo las que tienen `..` pasan por el resolvedor nuevo.

### Por qué no basta con normalizar el texto

Quitar `x/..` del texto cambia el resultado cuando `x` es un enlace simbólico. En Arch, `/lib -> usr/lib`:

- Linux: `/lib/../..` = `/usr/lib/../..` = `/`
- Normalizado como texto: `/lib/../..` → `/` (casualidad); pero `/lib/..` → `/` cuando Linux da `/usr`.

Por eso el `..` tiene que resolverse **sobre el árbol real**, siguiendo los enlaces, como hace el kernel.

### Resolvedor `resolver_raiz()`

Entrada: `dirfd`, la ruta y si es absoluta o relativa. Salida: la ruta real equivalente, con la garantía de que **nunca sube por encima de la raíz de la instancia**.

1. Punto de partida:
   - Ruta absoluta: la raíz de la instancia (profundidad 0).
   - Relativa con `AT_FDCWD`: el cwd real (`RAW getcwd`). Si no está dentro de `PREFIX` ni de `real_prefix` (por ejemplo, el cwd está en `/sdcard`), **no se toca**: es una ruta de Android y sigue igual que hoy.
   - Relativa con `dirfd`: `readlinkat("/proc/self/fd/N")`, con la misma regla.
2. Se recorre la ruta **hasta el penúltimo componente** (la carpeta que la contiene), uno por uno:
   - `.` o vacío: se ignora.
   - `..`: si la profundidad es 0, se queda en la raíz (como en un chroot); si no, se sube un nivel.
   - Nombre: si es un enlace simbólico (`readlinkat`), se reemplaza por su destino. Si el destino es absoluto con prefijo (así los guarda `symlinkat` hoy), se le quita (`unxlat`) y se sigue desde la raíz. Si es absoluto de Linux, desde la raíz. Si es relativo, desde la carpeta actual. Tope de 40 enlaces → `ELOOP`.
   - Un destino que caiga en una carpeta de `passthrough` (`/proc`, `/sdcard`...) sale del resolvedor tal cual, como hoy.
3. El **último componente** se deja al kernel, para no cambiar la semántica de `O_NOFOLLOW`, `AT_SYMLINK_NOFOLLOW`, `lstat`, `unlink`, `rename` o `readlink`. Excepción: si el último es `..` (o `.`), se resuelve también; es una carpeta.
4. El resultado pasa por el `xlat()` de siempre (prefijo y `passthrough`).

Profundidad y raíz se cuentan contra `PREFIX` **y** contra `real_prefix` (`/data/user/0/...` y `/data/data/...` son el mismo lugar).

### Dónde se engancha

- `XL()` / `xlat()` para rutas absolutas con `..`.
- Las syscalls con `dirfd` + ruta (`openat`, `newfstatat`, `statx`, `faccessat`, `mkdirat`, `unlinkat`, `renameat`/`renameat2`, `linkat`, `symlinkat` (lado del enlace), `readlinkat`, `fchmodat`, `fchownat`, `utimensat`, `mknodat`, `execveat`, `inotify_add_watch`, `name_to_handle_at`) y `chdir`, para las relativas con `..`.
- `execveat` con `dirfd` y ruta relativa: hoy arma `/proc/self/fd/N/<ruta>` (`android-path.c:2456`), y como `/proc` es de Android el kernel resuelve el `..` sin encerrarlo. Si la ruta tiene `..`, pasarla antes por el resolvedor con ese `dirfd` y ejecutar la ruta resultante. `fexecve` (`AT_EMPTY_PATH`, ruta vacía) no cambia.
- Vale también para los binarios fuera de la glibc (Go, estáticos): la capa seccomp propia (0015) ya los manda por `__android_path_syscall`.

### Código puro y testeable en el PC

El resolvedor va en un archivo propio, sin macros de glibc (por ejemplo `android-raiz.c` / `android-raiz.h`), con las tres operaciones que necesita (`readlinkat`, `getcwd`, `readlink` de `/proc/self/fd`) inyectadas como punteros a función o macros. Así:

- En la glibc se compila con `RAW(...)`.
- En el PC se compila con `gcc` normal contra un árbol de prueba en `/tmp` (carpetas y enlaces reales). Es la base de las pruebas de la historia.

## Plan (en orden; pruebas primero)

1. **Pruebas en el PC, en rojo.** Crear `glibc-prueba/pruebas/raiz/`:
   - `test_resolver.c` + `test.sh` (mismo estilo que `practica/02-traduccion-rutas/`): arma en `/tmp` un prefijo falso con `bin -> usr/bin`, `lib -> usr/lib`, enlaces absolutos con el prefijo puesto (como los que deja `symlinkat`), un enlace en bucle y una carpeta hermana (`../otra-instancia`). Casos en la tabla de criterios (C1–C12).
   - Primero falla porque el resolvedor no existe todavía.
2. **Prueba en el teléfono, en rojo.** `pruebas/raiz/en-telefono.sh`, que corre dentro de una instancia: los criterios C13–C20 imprimiendo `OK`/`FALLA` por línea y un resumen final. Correrla con la libc actual y guardar la salida en rojo en `NOTAS.md`.
3. **Implementar `android-raiz.c`** hasta que `test.sh` del PC pase entero.
4. **Engancharlo** en `android-path.c` (`xlat` + syscalls con `dirfd` + `chdir`). Generar `glibc/parches/0025-android-raiz-cerrada.patch` sobre 0001–0024 limpios.
5. **Compilar** en Docker (`glibc/compilar.sh`) y correr `glibc/verificar.sh` (desensambla la libc ya compilada: ninguna syscall con rutas fuera de `__android_path_syscall`). Probar la libc **aislada** en el teléfono (`LD_LIBRARY_PATH` a una copia, como dice AGENTS.md) con `en-telefono.sh` hasta verde.
6. **Regresión** (sección siguiente).
7. **Empaquetar:** `libldp.so` en `app/src/main/jniLibs/arm64-v8a/`, `libc.so.6` en la capa y en las instancias, respaldo `libc.so.6.00NN`, `apk/armar.sh sdk36`, `assembleSdk36Debug`. La instalación en el teléfono la hace el usuario o se hace desde el PC (instalar la libc o la APK desde dentro de la app mata la sesión).
8. Actualizar `NOTAS.md`, `PROYECTO.md` (fila de la glibc: parche 0025) y marcar B26 en `BACKLOG.md`.

## Criterios de aceptación

### En el PC (`pruebas/raiz/test.sh`, resolvedor aislado)

| # | Entrada (raíz = prefijo falso) | Resultado esperado |
|---|---|---|
| C1 | `/..` | raíz |
| C2 | `/../../..` | raíz |
| C3 | `/../otra-instancia/x` | `raíz/otra-instancia/x` dentro del prefijo (no existe → ENOENT al usarla), **nunca** la carpeta hermana |
| C4 | `/usr/../etc` | `raíz/etc` |
| C5 | `/lib/..` (con `lib -> usr/lib`) | `raíz/usr` (igual que Linux) |
| C6 | `/lib/../..` | raíz |
| C7 | relativa `..` con cwd = raíz | raíz |
| C8 | relativa `../../x` con cwd = `raíz/home/user` | `raíz/x` |
| C9 | `dirfd` = raíz, ruta `..` | raíz |
| C10 | enlace con destino absoluto con prefijo (`/data/.../usr/lib`) seguido de `..` | `raíz/usr` |
| C11 | bucle de enlaces + `..` | `ELOOP` |
| C21 | `execveat(dirfd = raíz, "../usr/bin/x")` | ejecuta `raíz/usr/bin/x` (resolvedor con `dirfd`), no `/proc/self/fd/N/../usr/bin/x` |
| C12 | ruta **sin** `..` | intacta, y el resolvedor no hace ninguna llamada (contador de llamadas a las funciones inyectadas = 0) |

### En el teléfono (`pruebas/raiz/en-telefono.sh`, dentro de una instancia Arch)

| # | Comando | Esperado |
|---|---|---|
| C13 | `cd / && ls ..` | igual que `ls /` |
| C14 | `ls /..` y `ls /../..` | igual que `ls /` |
| C15 | `cat /../<otra-instancia>/etc/hostname` | `No such file or directory` |
| C16 | `cd -P /.. && pwd` | `/` |
| C17 | `realpath /../..` y `readlink -f /lib/..` | `/` y `/usr` |
| C18 | `python3 -c "import os; print(sorted(os.listdir('/..')) == sorted(os.listdir('/')))"` | `True` |
| C19 | Binario estático o Go (fuera de la glibc) que abre `/..` | ve la raíz de la instancia (camino de la capa seccomp 0015) |
| C20 | Carpetas de Android: `ls /proc/self/..`, `ls /sdcard/..` | igual que con la libc actual (no se encierran) |

### Regresión (con la libc nueva instalada)

- `pacman -Sy` y `pacman -Qk pacman` en Arch; `apt-get update` en Debian.
- Abrir una terminal nueva (bash y zsh con starship), `sudo` del wrapper actual, scripts con `#!`.
- Arranque de sway (o del escritorio de la instancia) y `kitty`.
- `sshd` del supervisor (`service status sshd`).
- **Rendimiento:** `time find /usr > /dev/null` con la libc vieja y la nueva, 3 veces cada una; diferencia ≤ 5 % (las rutas sin `..` no deben pagar nada).

### De entrega (Definition of Done)

- Parche `0025-android-raiz-cerrada.patch` aplicado sobre 0001–0024 limpios.
- `pruebas/raiz/test.sh` verde en el PC; `en-telefono.sh` verde en el teléfono (salidas en rojo y en verde pegadas en `NOTAS.md`).
- Binarios sincronizados según AGENTS.md (`jniLibs`, capa, instancias, respaldo `libc.so.6.00NN`).
- `NOTAS.md`, `PROYECTO.md` y `BACKLOG.md` actualizados; commit.

## Fuera de alcance

- **Aislar instancias por seguridad.** Todas tienen el mismo UID real; esto es semántica de Linux, no un límite de seguridad (ver `ARQUITECTURA-USUARIOS.md`, "Límite").
- **Achicar `passthrough`** (sobre todo `data`, que deja ver `/data/user/0/<app>/files/instancias/...` por ruta completa): queda como historia aparte (B26b). Hay que inventariar antes qué usa `/data` (cargador en `/data/app`, `/data/local/tmp/proxy-ports.conf`, `adb-puerto`...).
- **`chroot(dir)` con `dir` distinto de `/`** (raíz virtual por proceso, para sshd privsep): va en B27, fase 4, y se apoya en este resolvedor.
- **Cambiar cómo se guardan los enlaces simbólicos** (hoy `symlinkat` escribe el destino absoluto con el prefijo): historia aparte (B28).
- **`/proc/<pid>/root` y `/proc/<pid>/cwd`**: siguen mostrando la ruta real.
- Escritorios, Java y la app: no se tocan.

## Riesgos

- **Semántica de enlaces:** por eso el último componente queda en manos del kernel y el `..` se resuelve sobre el árbol real, no como texto. Los casos C5, C6 y C10 lo cubren.
- **Concurrencia:** entre resolver y llamar al kernel alguien puede cambiar un enlace (TOCTOU). Es aceptable: no es un límite de seguridad.
- **cwd fuera del prefijo** (procesos lanzados en `/sdcard`): no se encierran (C20).
- **Rutas largas:** respetar `PATH_MAX` (devolver `ENAMETOOLONG` como `XL`).
