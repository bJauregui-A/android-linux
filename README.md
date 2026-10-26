# Linux en Android, sin root

Una **capa de compatibilidad** que corre distribuciones Linux oficiales (Arch Linux ARM, Debian), sin modificar y a velocidad nativa, dentro de una app de Android sin root. Una glibc parcheada adapta los programas a las reglas de Android, y la app hace de anfitrión gráfico y de sistema.

- **No es un emulador:** no se emula CPU ni hardware. Los binarios aarch64 corren directo sobre el procesador y el kernel del teléfono.
- **No es un contenedor:** Android no permite *namespaces*, *cgroups* ni `chroot` sin root.
- **No es proot:** no intercepta cada llamada al sistema con `ptrace`. La adaptación ocurre dentro de cada programa, en su libc.

Probado en un Redmi 15 5G (HyperOS 3, Android 16, bootloader bloqueado).

## Cómo funciona, en corto

| Pieza | Qué hace |
|---|---|
| glibc parcheada + cargador `libldp.so` | Traduce rutas (`/usr` → la carpeta de la instancia), da root virtual (`sudo` real con tu contraseña), y emula lo que Android bloquea o no tiene: SysV IPC, `/proc`, red virtual, `hostname` |
| Capa de seccomp propia | Atrapa lo que pasa por encima de la glibc: programas en Go, binarios estáticos |
| La app | Compositor Wayland propio, audio, portapapeles, notificaciones, red y reenvío de puertos, supervisor de servicios |
| Instancias | Cada una es un Linux completo (Arch o Debian) en su propia carpeta, con sus paquetes y su IP |

Los paquetes salen de los repositorios oficiales (`pacman`, `apt`); no se recompilan.

## Primeros pasos

1. Instala el APK.
2. En la app, **＋ CREAR**: elige la distro y un nombre.
3. El asistente pide usuario, contraseña, nombre del equipo, escritorio y módulos (zsh, utilidades, audio, SSH...).
4. Al terminar tienes una terminal de Linux. Si elegiste escritorio, se abre con el botón de escritorio de la instancia.

```sh
sudo id          # pide tu contraseña → uid=0(root)
sudo pacman -S htop      # Arch
sudo apt install htop    # Debian
```

## Red

Cada instancia tiene una **IP fija** dentro de una subred virtual:

| | Valor por defecto |
|---|---|
| Subred | `10.0.0.0/24` |
| Gateway (el teléfono) | `10.0.0.1` |
| Instancias | desde `10.0.0.2`, la primera libre al crearla |

- La IP se guarda al crear la instancia y no cambia aunque borres otras. Al borrar una instancia, su IP queda libre para la siguiente.
- Dentro de la instancia, la IP está en `/etc/virtual-ip`. Las demás instancias aparecen en `/etc/hosts` por su nombre:
  ```sh
  cat /etc/virtual-ip      # 10.0.0.3
  getent hosts debian-12345   # otra instancia, por nombre → 10.0.0.4
  ```
- Detrás, cada `10.0.0.N` es en realidad `127.0.0.N` del teléfono, así que **un servicio de una instancia escucha en su `127.0.0.N`, no en `127.0.0.1`**.
- Las subredes se ven y se crean en la app, botón **⇄ RED**.

## Reenvío de puertos

Para llegar a un servicio de una instancia desde otro equipo de tu red (por ejemplo un servidor web en Debian), se crea una regla **puerto del teléfono → instancia:puerto**.

### Puertos 1024 o mayores

Los abre la app directamente.

1. App → **⇄ RED** → *Reglas de reenvío*.
2. Puerto externo (en el teléfono), instancia y puerto interno. Por ejemplo `8080 → debian-12345:80`.
3. **＋ GUARDAR REGLA**.

Desde otro equipo de la misma Wi-Fi: `http://<IP del teléfono>:8080`.

> El puerto interno `22` se lleva al `8022` de la instancia, que es donde escucha `sshd`.

### Puertos menores a 1024 (80, 443, 22...)

Android no deja que una app normal abra puertos menores a 1024. El usuario `shell` de Android (el de `adb`) sí puede, así que esos puertos los abre un pequeño daemon que corre como `shell`, sin root.

**Una sola vez: vincular la depuración inalámbrica**

1. Android → *Opciones de desarrollador* → **Depuración inalámbrica**: actívala.
2. Toca **Vincular dispositivo con código de sincronización** y deja ese diálogo abierto.
3. En la terminal de la instancia:
   ```sh
   adb-conectar     # pide el código de 6 dígitos la primera vez
   ```
   Necesita `adb` en la instancia: `sudo pacman -S android-tools` (Arch) o `sudo apt install adb` (Debian).

**Crear la regla**

Desde la app (**⇄ RED**, igual que arriba; al poner un puerto < 1024 avisa que pasa por `shell`), o desde la terminal:

```sh
proxy-puertos add 80 debian-12345 80   # :80 del teléfono → puerto 80 de la instancia
proxy-puertos add 443 10.0.0.3          # también acepta la IP; sin puerto interno usa el mismo
proxy-puertos status                    # reglas y si están escuchando
proxy-puertos del 80                    # quitar una regla
proxy-puertos restart                   # volver a levantar todas
```

**A tener en cuenta**

- La depuración inalámbrica se apaga sin Wi-Fi o al reiniciar el teléfono. Entonces hay que correr `adb-conectar` otra vez y `proxy-puertos start`.
- Las reglas viven en `/data/local/tmp/proxy-ports.conf`, que comparten la app y el daemon.
- Para SSH al puerto 22 hay un atajo: `proxy-ssh-22`.

## Entrar por SSH desde el PC

Con el teléfono por USB:

```sh
adb forward tcp:8022 tcp:8022
ssh -p 8022 <usuario>@127.0.0.1
```

## Más información

- [`TECNICO.md`](TECNICO.md): arquitectura, estructura del repo, cómo compilar e instalar, pruebas y trampas conocidas.
- [`backlog.md`](backlog.md): lo que falta, en historias priorizadas.
