# B11 · Servidor X11 propio que dibuja directo en la surface

Como usuario, quiero usar los escritorios X11 (Openbox, XFCE X11 y los X11 de tasksel), para tener una alternativa sin Wayland.

B67 queda en pausa (`plan-b67.md`): su paso 12 (Xfce en Debian 12) espera esta historia.

## Avance (26-oct, para retomar)

- **Hechas, en el PC, sin commit:** pruebas 1a, 1b, 2, 3 y 4.
  - `x11/compilar.sh` (objetivos `xkbcomp`, `xserver`, `xkb`), `x11/parches/` (xtrans y xorg-server 21.1.13), `x11/ddx/android/` (copia de vfb y `jni.c` mínimo que arranca `dix_main` en un hilo).
  - El servidor toma la carpeta del socket de `X11_UNIX_DIR` y la del lock de `X11_LOCK_DIR`; si faltan, usa `/tmp`.
  - libXfont2 sin freetype; nettle estático; datos de teclado en `x11/assets/xkb/`.
  - `openbox` y `xfce-x11` en `orden-arch` con `PROBADO_EN` vacío; `sesion` nueva (sin probar) para gnome, gnome-flashback, cinnamon, mate y lxde.
- **Pendiente de autorización:** `pruebas/escritorios/menu.sh` fija la lista exacta de Arch y falla porque `orden-arch` ahora incluye `openbox xfce-x11` (criterio 6). Propuesta: actualizar solo el valor esperado.
- **Siguiente:** completar el DDX (Damage, copia a la surface, entrada por tubería), `ServicioX11` en Java, empaquetado en `apk/armar.sh`; luego las pruebas 5–13 en el teléfono (instala un APK: avisar antes).

## Estado de partida (26-oct)

- `escritorios/proveedores/x11-directo/proveedor.conf` solo declara `DISPLAY=:0` y espera `/tmp/.X11-unix/X0`. Nadie arranca un servidor X11: ningún escritorio X11 arranca, en ninguna distro (log de Debian 12: `xrdb: Can't open display ':0'`).
- Escritorios con `PROVEEDOR_PANTALLA=x11-directo`:
  - `openbox` y `xfce-x11` tienen paquetes de Arch, pero no están en `orden-arch` y figuran como `PROBADO_EN="arch"` sin haber arrancado nunca;
  - `xfce-x11`, `gnome`, `gnome-flashback`, `cinnamon`, `mate` y `lxde` tienen paquetes de Debian 12.
- Lo que ya resuelve el anfitrión Wayland y sirve de modelo:
  - dibujar en la surface (`anfitrion.c`, `ANativeWindow`);
  - el teclado, el mouse y el tacto (`Wayland.tecla/mover/boton/eje`, desde `WaylandActivity`);
  - el socket en una instancia, enlazado a las demás (`Wayland.iniciarPara`).

## Cómo se implementa

### Piezas y dónde viven

| Pieza | Qué es | Dónde |
|---|---|---|
| Receta de compilación | Script que baja `xorg-server` 21.1 y sus dependencias, aplica nuestros parches y compila con el NDK (clang para Android aarch64, `meson` con archivo de compilación cruzada) | `glibc-prueba/x11/compilar.sh`, `x11/parches/`, igual que `glibc/` |
| `libxserver.so` | El servidor como biblioteca con funciones JNI, no como ejecutable: necesita recibir la `Surface` de Android, y eso solo se hace desde Java | `jniLibs`, por `apk/armar.sh` |
| `libxkbcomp.so` | `xkbcomp` compilado para Android. Se guarda con nombre de biblioteca porque `nativeLibraryDir` es la única carpeta donde Android deja ejecutar | `jniLibs` |
| Datos de teclado | `xkeyboard-config` (solo `keycodes`, `types`, `compat`, `symbols`, `rules`) | assets del APK; la app los copia a `files/x11/xkb/` la primera vez |
| `ServicioX11` | Servicio de Android en **su propio proceso** (`android:process=":x11"` en el manifiesto) que carga `libxserver.so` y corre el servidor | `app/src/main/java/.../ServicioX11.java` |

### 1. La salida a la surface (DDX propio)

- **Base:** se parte de `hw/vfb` (el código de Xvfb), que ya hace un servidor X con el framebuffer en memoria y sin hardware. Se copia como `hw/android/` en un parche y se le agregan tres cosas:
  1. **Seguimiento de cambios:** se registra Damage sobre la pantalla. Cada vez que un cliente dibuja, queda anotada la región que cambió.
  2. **Copia a la surface:** en el *block handler* (lo que el servidor corre antes de dormir esperando clientes), si hay región cambiada y hay ventana: `ANativeWindow_lock`, copiar solo esos rectángulos, `ANativeWindow_unlockAndPost`.
  3. **Formato sin conversión:** la ventana se configura en BGRA (formato 5 de HAL, el mismo truco que `anfitrion.c` con `VENTANA_BGRA`). El visual de 24 bits de X11 guarda los píxeles igual en memoria, así que la copia es un `memcpy` por fila.
- **Hilos:** el bucle del servidor corre en un hilo propio del proceso `:x11`. Java nunca toca el estado del servidor: las llamadas JNI (`ventana`, `tecla`, `mover`, `boton`, `eje`) escriben un mensaje en una tubería, y el servidor la vigila con `SetNotifyFd` y procesa los mensajes en su propio hilo. Es lo mismo que hace `anfitrion.c` con su cola de eventos (`evfd`).

### 2. La entrada

- En `hw/android/` se crean dos dispositivos de entrada con `AddInputDevice`: un teclado y un puntero absoluto.
- Al leer de la tubería:
  - una tecla evdev pasa a keycode X sumando 8 (es la convención de `evdev` en XKB) y entra con `QueueKeyboardEvents`;
  - el puntero entra con `QueuePointerEvents` en coordenadas absolutas;
  - los botones 1 a 3 y la rueda como botones 4 a 7.
- La vista (`WaylandActivity`) ya convierte tacto, mouse y teclado de Android en eventos evdev para Wayland. Cuando la sesión es X11, manda esos mismos eventos a `ServicioX11` en lugar de a `Wayland.*`. No se escribe otra lógica de entrada.

### 3. Teclado (XKB) sin depender de la distro

- `xorg-server` no trae los mapas de teclado: al arrancar ejecuta `xkbcomp` y lee los archivos de `xkeyboard-config`. Normalmente los toma del sistema, pero en Android no existen, y no deben salir de la instancia, porque cada distro tiene versiones distintas.
- Se compila `xkbcomp` para Android (necesita `libxkbfile` y `libX11`, también compiladas para Android). Al arrancar, el servidor recibe las rutas a `libxkbcomp.so` (`XkbBinDirectory`) y a `files/x11/xkb/` (`-xkbdir`).
- Distribución `latam` por defecto, igual que en Wayland: `-xkbmap latam`, o el equivalente con `XkbSetRulesDflts` en el DDX.
- Alternativa más simple si `xkbcomp` cuesta: compilar en el PC un `latam.xkm` ya listo y cargarlo directo. Funciona, pero solo con esa distribución.

### 4. Socket solo en archivo, sin socket abstracto ni TCP

- **Al compilar:** `-Dlisten_tcp=false -Dlisten_local=false -Dlisten_unix=true`. En Linux, `local` es el socket abstracto y `unix` es el socket en archivo. *A verificar:* los nombres exactos de las opciones en el `meson_options.txt` de 21.1.
- **Ruta del socket:** `xtrans` tiene fija la carpeta `/tmp/.X11-unix`, y el servidor también fija `/tmp/.X0-lock`. En Android no existe `/tmp`, así que un parche cambia las dos rutas por una que pasa la app al arrancar: `files/x11/.X11-unix/X0` y `files/x11/.X0-lock`.
- **Llegar desde cada instancia:** la app crea en cada instancia el enlace `/tmp/.X11-unix/X0` → `files/x11/.X11-unix/X0`, como hace hoy `Wayland.iniciarPara` con `wayland-0`.
  - Un cliente de cualquier distro, con `DISPLAY=:0`, primero prueba el socket abstracto. Como no existe, falla al instante y abre `/tmp/.X11-unix/X0`.
  - La glibc traduce esa ruta al prefijo de la instancia, y el kernel sigue el enlace hasta el socket real.
- Por qué importa: los sockets abstractos no tienen permisos de archivo, y otras apps del teléfono podrían conectarse y leer teclas o la pantalla. El socket en `files/` solo lo ve nuestra app.

### 5. MIT-SHM desactivado

- `-Dmitshm=false` al compilar. Los clientes preguntan qué extensiones hay; si no está, dibujan con `XPutImage` por el socket.
- Por qué: con MIT-SHM el cliente crea un segmento con `shmget` y le pasa al servidor solo su número. Nuestra glibc emula `shmget` con archivos dentro del prefijo (parche 0008), y el servidor, que es bionic, no puede abrir ese segmento por número. Funcionaría con la versión 1.2 de la extensión, que pasa un descriptor de archivo, pero eso queda fuera de alcance.

### 6. Proceso aparte

- `ServicioX11` se declara con `android:process=":x11"`: Android lo corre en otro proceso Linux de la misma app (mismo usuario, mismos archivos).
- La vista se conecta a él por Binder y le pasa la `Surface` (que se puede mandar entre procesos) cada vez que se crea, cambia o destruye, junto con los eventos de entrada.
- Si el proceso `:x11` muere, la app recibe el aviso de Binder (`linkToDeath`), la vista vuelve al estado "sin escritorio" y la próxima vez que se abra el escritorio se arranca otro proceso. `xorg-server` tiene mucho estado global y no se puede reiniciar dentro del mismo proceso: por eso un proceso nuevo por sesión.

### 7. Lo que se desactiva al compilar

- `-Dglx=false -Ddri1=false -Ddri2=false -Ddri3=false` (la GPU es B36).
- `-Dxorg=false -Dxephyr=false -Dxnest=false -Dxvfb=false -Dxwayland=false`: solo se compila nuestro DDX.
- `-Dudev=false -Dsystemd_logind=false -Dxdmcp=false -Dint10=false -Dsecure-rpc=false`.
- SHA1 (lo exige el servidor): Android no trae ninguna de las bibliotecas habituales, así que se compila una de las que acepta `-Dsha1=` (por ejemplo `libnettle`). *A verificar:* cuál cuesta menos.
- Fuentes: solo las integradas del servidor (`fixed`, `cursor`), sin ruta de fuentes. `xterm` y los gestores de ventanas usan esas; los escritorios modernos dibujan su texto del lado del cliente.

### 8. Arranque de una sesión X11

1. `TerminalService.iniciarEscritorioPara` lee el `escritorio.conf` del escritorio elegido. Si su `PROVEEDOR_PANTALLA` es `x11-directo`, arranca `ServicioX11` antes de lanzar la sesión.
2. `ServicioX11` arranca el servidor con el tamaño y el DPI de la pantalla (`-screen 0 <ancho>x<alto>x24 -dpi <dpi>`), y la app crea el enlace del socket en la instancia.
3. El proveedor `x11-directo` ya espera `/tmp/.X11-unix/X0` (`COMPROBACION_READY=socket-x11`). Cuando aparece, `sesion-android` corre la sesión del escritorio (`startxfce4`, `openbox-session`...) con `DISPLAY=:0`.
4. Al cerrar la sesión, la app detiene `ServicioX11` y su proceso termina.

### Por qué sirve en cualquier distro

- El servidor, `xkbcomp` y los datos de teclado van en el APK. La instancia no aporta nada del servidor.
- Lo único que ve la instancia es `DISPLAY=:0` y el enlace `/tmp/.X11-unix/X0`. Ambos se crean igual en cualquier prefijo.
- Los clientes usan la `libX11`/`libxcb` de su propia distro. El protocolo X11 es el mismo en todas.
- Una distro nueva solo necesita declarar los paquetes de sus escritorios X11 (el mecanismo de B67).

## Criterios de aceptación

1. **El servidor arranca para una sesión X11**
   - Dado una instancia con un escritorio X11 elegido,
   - cuando abro el escritorio,
   - entonces la app arranca el servidor X11 en su propio proceso, aparece `/tmp/.X11-unix/X0` en la instancia y `xdpyinfo` responde con el tamaño de la pantalla.

2. **Funciona igual en las dos distros**
   - Dado una instancia de Arch y una de Debian 12,
   - cuando cada una abre su sesión X11,
   - entonces ambas usan el mismo servidor del APK, sin instalar nada de X11 del lado del servidor en la instancia.

3. **Imagen y entrada**
   - Dado un escritorio X11 abierto,
   - entonces se ve en la pantalla del teléfono, y el teclado (con la distribución `latam`), el mouse y el tacto le llegan.

4. **Sin puertas para otras apps**
   - Dado el servidor corriendo,
   - entonces no hay socket abstracto de X11 ni puerto TCP; solo el socket en archivo dentro de los datos de la app.

5. **Un fallo del servidor no tumba la app**
   - Dado el servidor corriendo,
   - cuando su proceso muere,
   - entonces la app sigue abierta, y al volver a abrir el escritorio el servidor arranca de nuevo.

6. **Escritorios X11 en el menú, sin probar**
   - Dado Arch, Openbox y XFCE X11 aparecen en el menú.
   - Dado Debian 12, aparecen Xfce, GNOME, GNOME Flashback, Cinnamon, MATE y LXDE.
   - Todos con `PROBADO_EN` vacío, que se muestra como experimental.

7. **Cierre**
   - B11 se cierra cuando arrancan y responden al teclado y al mouse estos tres: Openbox en Arch, XFCE X11 en Arch y Xfce en Debian 12.
   - GNOME, GNOME Flashback, Cinnamon, MATE y LXDE se prueban en Debian 12 y se anota el resultado. Si alguno falla por algo propio del escritorio, sigue en su historia (B73–B78) y no bloquea B11.
   - `PROBADO_EN` queda vacío en todos por ahora.

## Fuera de alcance

- Aceleración por GPU (GLX, DRI3, Present): B36.
- Cada ventana X11 como ventana propia del anfitrión (modo sin escritorio, "rootless").
- Cambiar el tamaño al rotar la pantalla o al cambiar de ventana en Android (se toma el tamaño al arrancar).
- Portapapeles entre X11 y Android.
- MIT-SHM (memoria compartida pasada como descriptor, versión 1.2 de la extensión).
- Dos sesiones X11 a la vez en instancias distintas (como hoy con los compositores, abrir una cierra la otra).
- Fuentes de la instancia en el servidor (solo las integradas).
- Marcar escritorios como probados (queda para después de B11).

## Pruebas, en orden

En el PC (`glibc-prueba/pruebas/x11/`):

1. **Compilación.** `x11/compilar.sh` produce `libxserver.so` y `libxkbcomp.so`: ELF aarch64 para Android, y sus bibliotecas necesarias (`NEEDED`) son solo las del sistema Android o las que van en el APK.
2. **Extensiones y socket.** La configuración de `meson` que usa el script deja apagados GLX, DRI, MIT-SHM, XDMCP, TCP y el socket abstracto, y el parche de `xtrans` toma la carpeta del socket que le pasa la app.
3. **Datos de teclado.** Con los datos de `xkeyboard-config` que van en el APK, `xkbcomp` del PC compila el mapa `evdev` con distribución `latam` sin errores.
4. **Proveedor y menú.**
   - `orden-arch` incluye `openbox` y `xfce-x11`;
   - los siete escritorios X11 tienen `PROBADO_EN` vacío;
   - el menú de cada distro los muestra como experimentales (sobre las funciones de B67).

En el teléfono (`scripts/probar-en-telefono.sh`, solo lectura salvo que se indique):

5. **Arranque en Arch.** Con `ServicioX11` arrancado por la app: existe el enlace `/tmp/.X11-unix/X0`, `xdpyinfo -display :0` responde con el tamaño de la pantalla y su lista de extensiones no trae GLX, MIT-SHM ni DRI.
6. **Arranque en Debian 12.** Lo mismo, con `xdpyinfo` de `x11-utils`.
7. **Sin socket abstracto ni TCP.** `/proc/net/unix` no tiene `@/tmp/.X11-unix/X0`, y no hay nadie escuchando en el puerto 6000.
8. **Imagen.** Un cliente simple (`xterm`) se dibuja. `xwd -root -display :0` desde la instancia da una imagen que no está toda negra.
9. **Proceso aparte.** Matar el proceso del servidor no cierra la app, y reabrir el escritorio lo arranca otra vez. Toca el teléfono: avisar antes.
10. **Openbox en Arch.** Se instala desde el menú y arranca. Captura con `xwd`. Teclado y mouse los comprueba el usuario a mano.
11. **XFCE X11 en Arch.** Igual que la 10.
12. **Xfce en Debian 12.** Igual que la 10. Destraba el paso 12 de B67.
13. **GNOME, GNOME Flashback, Cinnamon, MATE y LXDE en Debian 12.** Se prueba cada uno y se anota el resultado en su historia.

Paso mínimo de interfaz: en la app no cambia nada visible. El escritorio X11 se abre con el mismo botón y la misma vista que los Wayland, y la vista manda la entrada al servidor X11 cuando la sesión es X11.

Al cerrar:
- actualizar `TECNICO.md`: el servidor X11, dónde vive su socket, y por qué no hay socket abstracto ni MIT-SHM;
- empaquetar el binario en el APK (`jniLibs`) y sincronizarlo a las instancias, como pide `AGENTS.md`.
