# Usuarios y permisos virtuales

Diseño para que los programas Linux **oficiales** (`sudo`, `useradd`, `groupadd`, `passwd`, `chown`, `sshd`, apache, postgres...) funcionen como en un PC dentro de la app, sin wrappers. Ítem B27 de `BACKLOG.md`. Escrito el 2026-10-25. **Fases 1, 2 y 3 implementadas** (80ª a 82ª sesión, parches 0026, 0027 y 0028); el resto sigue en diseño.

## Por qué

Android le da a la app **un solo UID real** (en el Redmi, 10478 = `u0_a478`). Todo proceso Linux, todo archivo y todo socket es de ese UID. Hoy se tapa con piezas sueltas:

| Pieza | Qué hace hoy | Dónde |
|---|---|---|
| `GLIBC_FAKEROOT=1` | `get*id` devuelven 0; `chown`/`fchown` con EPERM se dan por buenos (no se guarda nada) | `android-path.c`, línea ~2135 |
| `set*id` | Bloqueadas por el seccomp de apps; se responden "ok" solo si no cambian nada (`setxid_igual`), o siempre con fakeroot | parche 0010 |
| `stat` | Muestra el UID real de la app como dueño de todo | — |
| `chroot` | Solo acepta `chroot("/")` | `android-path.c`, `case __NR_chroot` |
| `linkat` | Copia el archivo (Android no deja crear enlaces duros) | `android-path.c:527` |
| `sudo` | Wrapper que exporta `GLIBC_FAKEROOT=1` | `AdaptadorArchArm64`, `AdaptadorDebianArm64`, `bootstrap-debian.py` |
| Usuarios de sistema | Se agregan a mano a la base (`sshd`, `_ssh`, grupos de Debian) | `bootstrap-debian.py`, `instalar.sh` |
| Usuario principal | En `/etc/passwd` con el UID real de la app (`U=$(id -u)`) | `primer-arranque.sh:279` |

Síntomas: `groupadd` falla (`lock file already used (nlink: 1)`, apache2/ssl-cert en Debian, 25-oct); `sudo` no es el real (sin `/etc/sudoers` ni PAM); los demonios que bajan privilegios (apache → `www-data`, sshd privsep, postgres) no cambian de usuario y los archivos que crean no tienen el dueño esperado.

## Qué se probó (2026-10-25, Redmi, instancia `dev-6918`, `Seccomp: 2`)

| Prueba | Resultado |
|---|---|
| `setxattr`/`getxattr` `user.*` en archivo | ✅ |
| Ídem en carpeta | ✅ |
| xattr tras `rename` | ✅ se conserva |
| xattr `user.*` en enlace simbólico | ❌ EPERM (igual que en cualquier Linux: el kernel no los permite en symlinks) |
| `openat2` (con o sin `RESOLVE_IN_ROOT`) | ❌ ENOSYS: el seccomp de apps la bloquea (ver B26) |

## Límite

Esto **imita** a Linux; no es seguridad. Por debajo sigue habiendo un UID, y cualquier programa puede saltarse la capa (syscalls con la `MARCA` de la capa seccomp, o leyendo los archivos por su ruta real). El objetivo es que el software se comporte bien, no aislar usuarios entre sí.

## Diseño

### 1. Credenciales virtuales por proceso

- Estado en la glibc: `ruid, euid, suid, fsuid`, `rgid, egid, sgid, fsgid` y la lista de grupos suplementarios.
- `getuid`, `geteuid`, `getresuid`, `getgroups` (y los de gid) devuelven el estado virtual. `setuid`, `seteuid`, `setreuid`, `setresuid`, `setfsuid`, `setgroups` (y los de gid) lo cambian **con las reglas de Linux**: solo euid 0 puede cambiar a cualquiera; los demás solo entre sus ruid/euid/suid. Así los programas que comprueban que bajaron privilegios (sshd, apache) ven lo que esperan.
- **Herencia:** en `fork`/`clone` se copia sola (memoria del proceso). En `execve`, igual que hoy con `GLIBC_PREFIX` y `GLIBC_LOADER` (`env_prefix`, `env_loader`), la glibc **reinyecta** una variable interna (`GLIBC_CRED=ruid,euid,suid:rgid,egid,sgid:grupos`) aunque el programa haya limpiado el entorno (`sudo` con `env_reset`, `env -i`). Al iniciar, se lee de `/proc/self/environ` como las otras.
- **Valor inicial** (proceso lanzado por la app, sin `GLIBC_CRED`): el usuario principal de la instancia. Para no reescribir instancias existentes, su uid virtual es **el UID real de la app** (el que ya está en `/etc/passwd`). Root es 0 y el resto de usuarios usa sus números de `/etc/passwd`.
- `GLIBC_FAKEROOT=1` pasa a ser equivalente a `GLIBC_CRED` con todo en 0.

### 2. Dueño virtual por archivo

- Se guarda en un xattr `user.linux.owner` (`uid:gid`, texto corto). Viaja con el archivo en `rename` y no hay base de datos aparte que se desincronice.
- **Lectura:** `stat`, `fstat`, `newfstatat`, `statx` hacen un `getxattr` y reemplazan `st_uid`/`st_gid`.
- **Sin xattr, regla por ubicación:** dentro de `/home/<usuario>` es de ese usuario; en el resto (`/usr`, `/etc`, `/var`...) es de `root:root`. Así las instancias ya instaladas se ven bien sin migrar nada.
- **Escritura:** `chown`, `fchown`, `fchownat`, `lchown` escriben el xattr (o lo borran si coincide con la regla, para no llenar el disco de atributos). Ya no hace falta fingir el EPERM.
- **Archivos nuevos** (`openat` con `O_CREAT`, `mkdirat`, `mknodat`): si el fsuid/fsgid del proceso no coincide con la regla de esa ubicación, se escribe el xattr. Respeta el bit setgid de la carpeta (el grupo se hereda), como Linux.
- **Enlaces simbólicos:** no admiten xattr. `lstat` informa el dueño de la carpeta que los contiene, y `lchown` se acepta sin guardar nada. En Linux el dueño de un symlink casi nunca importa (solo con `protected_symlinks` en carpetas con sticky bit).
- **Modo (permisos):** el modo real ya funciona. El dueño real de todo es la app, así que `chmod` siempre se puede, incluidos los bits setuid y setgid; `/data` va con `nosuid` y el kernel los ignora al ejecutar. **No hace falta guardarlo aparte.**

### 3. setuid y setgid virtuales en `execve`

- Si el ejecutable tiene el bit setuid (modo real) y su dueño virtual es U, el proceso nuevo arranca con `euid = suid = U` (y lo mismo con setgid). La glibc ya resuelve cada `execve` (cargador, `#!`), así que el chequeo cae en el mismo lugar.
- Con esto funciona el **`sudo` real**: comprueba que su binario sea de root con setuid (stat virtual), que `/etc/sudoers` sea `root 0440`, pide la contraseña por PAM (`pam_unix` lee `/etc/shadow` como root virtual) y ejecuta como el usuario destino. Lo mismo `su`, `passwd`, `unix_chkpwd`, `newgrp`. **El wrapper de `sudo` se retira.**

### 4. Lo que un root virtual intenta y Android no deja

Al verse como root, los programas toman caminos privilegiados que antes no tomaban. Cada uno hay que emularlo o responderlo de forma creíble:

| Operación | Quién la usa | Respuesta |
|---|---|---|
| `chroot(dir)` | sshd privsep (`/run/sshd`, `/var/empty`), vsftpd, postfix | Raíz virtual por proceso: el prefijo pasa a ser `PREFIX + dir`, se hereda y viaja por `execve` como `GLIBC_PREFIX`. Se apoya en B26 (normalizar `..`). |
| `setgroups`, `initgroups` | sshd, sudo, login, cron | Estado virtual (pieza 1) |
| `capset`, `prctl(PR_CAPBSET_*)`, `PR_SET_KEEPCAPS` | sshd, systemd-ish, ping | Ya hay un shim de `prctl` (0022); guardar las capacidades virtuales y devolverlas en `capget` |
| `setrlimit` por encima del tope duro | demonios | Aceptar y recordar el valor, devolverlo en `getrlimit` |
| `mount`, `umount`, `unshare`, `setns` | contenedores, algunos postinst | EPERM, como root en un contenedor sin privilegios. No se finge. |
| `kill` a un pid de otro usuario virtual | — | Se permite (mismo UID real); no se comprueba |

### 5. Bloqueo de shadow (`useradd`, `groupadd`, `passwd`, `chpasswd`)

- Shadow bloquea con `link(archivo.PID, archivo.lock)` y luego exige `st_nlink == 2` en `archivo.PID`. Como `linkat` copia, el nlink queda en 1 y aborta.
- Arreglo con la misma base: cuando `linkat` tiene que copiar, marca **las dos** copias con un xattr `user.linux.nlink` que guarda el nombre del par. `stat` informa `st_nlink = 2` mientras exista el otro. `unlink` de uno de los dos lo baja a 1. Si dos procesos compiten, gana el que crea primero el `.lock` (la copia usa `O_EXCL`), que es lo que shadow necesita.
- Con esto `/etc/passwd`, `/etc/group`, `/etc/shadow` y `/etc/gshadow` siguen siendo **la única** base de usuarios; las herramientas son las de la distro.

### 6. Chequeo de permisos (opcional, apagado al principio)

- El kernel deja hacer todo (es el dueño real de todo). Para ver los errores normales de Linux ("Permission denied" de un usuario sobre `/etc/shadow`, `sshd` rechazando un `authorized_keys` con permisos abiertos...), `openat`, `faccessat`, `execve`, `unlinkat` y `renameat` pueden comprobar el modo virtual contra las credenciales virtuales antes de llamar al kernel.
- Cuesta un `stat` y un `getxattr` más por operación: se activa con una variable (`GLIBC_PERMISOS=1`) y se mide antes de dejarlo por defecto.

### 7. Lo que se ve desde fuera

- `/proc/<pid>/status` (líneas `Uid:` y `Gid:`): lo genera el kernel con el UID real. `ps`, `top` y `htop` mostrarían `u0_a478`. Siguiente paso posible: incluirlo en el `/proc` sintético (0006) para el propio proceso y para los hijos que publiquen su `GLIBC_CRED`.
- La app (fase final): lista de usuarios de la instancia (lee `/etc/passwd`), con qué usuario abre la terminal (inicia con ese `GLIBC_CRED`) y cambio de contraseña (corre el `passwd` oficial).

## Costo

- Un `getxattr` extra en cada `stat` sobre rutas del prefijo. Los `stat` son la syscall más frecuente (pacman, `ls -l`, compiladores): medir con `pacman -Qk` y `ls -lR /usr` antes y después. Si pesa, hay dos atajos: una caché por proceso de inode → dueño, o leer el xattr solo fuera de `/usr` (que por regla es todo de root).
- Un `setxattr` al crear archivos solo cuando el dueño difiere de la regla (raro: demonios con su usuario, `/home` de otros usuarios).

## Fases

1. ✅ **Credenciales virtuales** (pieza 1) + `stat` con dueño virtual y regla por ubicación (pieza 2, solo lectura). Criterio: `id`, `ls -l /etc/shadow` (root), `ls -l ~` (usuario) y `sudo -u nobody id` con el wrapper actual.
2. ✅ **`chown` persistente + archivos nuevos + bloqueo de shadow** (piezas 2 y 5). Criterio: `sudo groupadd prueba`, `sudo useradd -m prueba`, y `apt install apache2` en Debian sin error de `ssl-cert` (`dpkg --configure -a` limpio).
3. ✅ **setuid virtual + `sudo` real** (pieza 3). Criterio: retirar el wrapper; `sudo -l`, `sudo -i`, contraseña por PAM, `/etc/sudoers` respetado.
4. **Operaciones de root** (pieza 4, sobre todo `chroot` virtual con B26). Criterio: `sshd` iniciado por el supervisor como root, con privsep; apache con workers como `www-data` (`ps` o `/proc` sintético).
5. **Chequeo de permisos** (pieza 6) y **pantalla de usuarios en la app**.

Cada fase: libc nueva probada aislada antes de instalarla (AGENTS.md), con respaldo `libc.so.6.00NN`, y empaquetada en `jniLibs`/capa.

## Decisiones tomadas en la fase 1 (80ª)

- **El usuario principal conserva el UID real de la app** (10478): no se migra nada.
- **Regla por ubicación sin xattr:** root en `/`, `/usr`, `/etc`, `/var`, `/opt`, `/bin`, `/sbin`, `/lib`, `/lib64`, `/boot`, `/root`, `/srv` y `/run` (salvo `/var/tmp` y `/run/user`); usuario principal en el resto (`/home`, `/tmp`, `/mnt`...). Más fina que "root fuera de `/home`": `/tmp` y `/run/user` deben ser del usuario (tmux, Qt y dbus comprueban el dueño).
- **`GLIBC_CRED`** = `r,e,s,f:r,e,s,f:grupos`, reinyectada en cada `execve`. `GLIBC_FAKEROOT=1` recién pedido da todo en 0; no se puede falsificar por entorno.
- "Privilegiado" (equivale a CAP_SETUID/SETGID/CHOWN) = euid virtual 0.
- Trampa de compilación: las syscalls de `syscalls.list` (`getgroups`, `setfsuid`...) necesitan un `.c` propio y borrar `build/sysd-syscalls` y los `.o` viejos.

## Decisiones tomadas en la fase 2 (81ª)

- Solo escribe xattr de dueño en archivos nuevos quien **no** es el usuario principal (fsuid/fsgid distintos de los de la app) y cuando la regla de la ubicación no coincide.
- El cerrojo de shadow se resuelve con `user.linux.owner = "u:g:L"` + `user.linux.par` (ruta de la otra copia); `st_nlink = 2` mientras el par exista (sin hook en `unlink`).
- Pendiente de la fase: bit setgid de carpetas (el grupo no se hereda); `chown` no limpia setuid/setgid del archivo.
- Para `setpriv` y similares (cambian uid antes que gid) hace falta `PR_SET_KEEPCAPS` (fase 4).

## Preguntas abiertas

- ~~¿El usuario principal mantiene el UID real?~~ Sí (ver arriba).
- Nombre y formato final de los xattr (`user.linux.owner`, `user.linux.nlink`). Ojo: `cp -a`, `tar --xattrs` y `rsync -X` los copian, y eso está bien (el dueño viaja con el archivo).
- ¿El `/proc` sintético debe mostrar los usuarios virtuales desde la fase 1?

## Referencias

- `fakeroot` (modo `-s`/`-i`, base de datos en archivo) y `pseudo` (Yocto, SQLite): mismo problema, resuelto con una base de datos externa. Aquí los xattr evitan esa base.
- `proot` (`-0`, extensión `fake_id0`): credenciales virtuales con ptrace; misma idea, pero por syscall interceptada en vez de dentro de la libc.

## Decisiones tomadas en la fase 3 (82ª)

- El setuid/setgid vale solo para el programa final del `execve` (un script no); el hijo recibe el dueño/grupo virtual como efectivo, guardado y fs. Todo `execve` copia el efectivo al guardado, como Linux.
- El `sudo` real viene del paquete de la distro, instalado en el primer arranque; el bit setuid se pone a mano (el `tar` de la base no lo conserva). La regla del usuario principal pide contraseña. Marca: `/etc/sudoers.d/10-linux-android`.
- Root virtual también salta los permisos de **escritura** de archivos (`abrir_root`); falta lo mismo para carpetas sin `x`/`w` y para lectura (fase 5, chequeo de permisos).
