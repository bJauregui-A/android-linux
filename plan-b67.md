# B67 · Menú de Debian 12 como tasksel, paquetes por distro y versión, y XFCE funcionando

Como usuario de Debian 12, quiero que el menú muestre los escritorios que ofrece su instalador (tasksel) con los paquetes de Debian 12, y tener XFCE probado y funcionando, para elegir como en una instalación real.

Deja el mecanismo para las demás distros (B65 Arch, B68 Debian 13, B69/B70 Ubuntu).

Estado de partida (25-oct):
- El menú (`apk/primer-arranque.sh`, `escritorios/orden`) es el mismo para todas las distros.
- Los paquetes de cada escritorio salen de `escritorios/<id>/paquetes.txt` (nombres de Arch) o de `paquetes-<backend>.txt`, que nadie tiene. Debian usó los nombres de Arch y la instalación de XFCE abortó: `labwc`, `xfdesktop`, `garcon` y `exo` no existen en bookworm (comprobado con `apt-cache policy` en `debian_desktop-74818`).
- `ESTADO=probado` vale para todas las distros.
- `/etc/os-release`: Arch ARM trae `ID=archarm`, `ID_LIKE=arch` y no trae `VERSION_ID` (rolling). Debian trae `ID=debian` y `VERSION_ID="12"`.

Avance (27-oct): se retoma tras cerrar B11 (`1f48d38`), que deja X11 directo funcionando en el teléfono.
- Hechas las pruebas 1–9: `5be8fe2`, `c52f304`, `30f18b5`, `7005827`, `1af3741`, `434c153`, `d92b691`, `87acc13`, `7abf118` y `fac2815` (`distro_version` lee `/usr/lib/os-release` si falta `/etc/os-release`).
- `87acc13` declaró paquetes de `debian-12` para los 8 escritorios de tasksel, no solo para Xfce. Por eso el menú de Debian 12 muestra los 8 como experimentales, y no solo Xfce y la consola. Los nombres se comprobaron contra el índice de bookworm, pero no con `apt-cache` en el teléfono.
- B11 sumó a la base de Debian pines, hold de libc, usuarios, gconv, un bus de sistema para Cinnamon y GNOME, y la liberación de requisitos frenados (`pruebas/debian/requisitos.sh`).
- Ningún escritorio tiene `debian-12` en `PROBADO_EN`. `xfce-x11` tiene `PROBADO_EN=""` (tampoco está probado en `arch`).
- Hechas las pruebas 10 (`95d9697`) y 11 (sin commit). Falta la 12.

## Criterios de aceptación

1. **Distro y versión de la instancia**
   - Dado el `/etc/os-release` de una instancia,
   - cuando el instalador arma el menú,
   - entonces usa `debian-12` para Debian 12 y `arch` para Arch ARM (rolling, sin versión).

2. **Paquetes por distro y versión**
   - Dado un escritorio con paquetes declarados para `debian-12`,
   - cuando lo instalo en Debian 12,
   - entonces se instalan esos paquetes y nunca los de otra distro o versión.

3. **Sin paquetes para la versión, no aparece**
   - Dado un escritorio sin paquetes para `debian-12`, aunque los tenga para Arch o para `debian-13`,
   - cuando abro el menú en Debian 12,
   - entonces ese escritorio no aparece.

4. **El menú de Debian 12 es el de tasksel**
   - Dado Debian 12,
   - cuando abro el menú,
   - entonces muestra, en el orden de tasksel, los escritorios de tasksel (GNOME, Xfce, GNOME Flashback, KDE Plasma, Cinnamon, MATE, LXDE, LXQt) que tienen paquetes para `debian-12`, y la opción de consola.
   - Hoy los 8 tienen paquetes declarados (`87acc13`) y aparecen todos. Xfce es X11 con `xfwm4`, como lo instala Debian. Solo Xfce se prueba en esta historia; los demás siguen como experimentales hasta su historia (B73–B78 y siguientes).

5. **Probado o experimental, por distro y versión**
   - Dado un escritorio probado en `arch` pero no en `debian-12`,
   - cuando abro el menú en Debian 12,
   - entonces aparece como experimental. En Arch sigue como probado.

6. **Arch no cambia**
   - Dado Arch,
   - cuando abro el menú,
   - entonces muestra los mismos escritorios, en el mismo orden, con los mismos paquetes y el mismo estado que hoy.

7. **XFCE funciona en Debian 12**
   - Dado una instancia Debian 12 nueva,
   - cuando elijo Xfce en el menú,
   - entonces la instalación termina, XFCE arranca y se ve, y vuelve a arrancar después de cerrar y abrir la app.
   - Recién entonces queda marcado como probado en `debian-12`.

## Fuera de alcance

- El menú de Arch según archinstall (B65); Arch conserva su menú actual.
- Debian 13 y la unificación con `/usr` (B68). Ubuntu (B69, B70).
- Probar los demás escritorios de tasksel (GNOME, Flashback, KDE Plasma, Cinnamon, MATE, LXDE, LXQt) en Debian 12. Ya tienen paquetes y salen en el menú como experimentales.
- Firefox dibuja vacío en Xfce X11 (sin DRI3): es B36, no bloquea la prueba 12.
- Mostrar en el menú si un escritorio usa Wayland o X11 (B64).
- Los módulos opcionales (`apk/paquetes-<módulo>-apt.txt`: utilidades, zsh, audio...) y la base de escritorio (`apk/paquetes-escritorio-apt.txt`) siguen por gestor de paquetes, no por versión.
- `labwc` en Debian 12 (traerlo de Debian 13 o compilarlo).

## Pruebas, en orden

Pruebas de shell en el PC, en `glibc-prueba/pruebas/escritorios/`, que extraen las funciones de `apk/primer-arranque.sh` (como `pruebas/usuario/registrar.sh`) y trabajan sobre carpetas de escritorios de mentira en un directorio temporal.

1. Distro y versión desde un `os-release` de Debian 12 → `debian-12`.
2. Distro y versión desde un `os-release` de Arch ARM (`ID=archarm`, sin `VERSION_ID`) → `arch`.
3. Paquetes de un escritorio para `debian-12` cuando los declara → esa lista.
4. Paquetes de un escritorio para `debian-12` cuando solo los declara para `arch` y `debian-13` → vacío (no cae a otra distro ni a otra versión).
5. Menú de `debian-12`: dada la lista de tasksel y escritorios con y sin paquetes para `debian-12`, devuelve solo los que tienen, en el orden de tasksel, más la consola.
6. Menú de `arch`: devuelve los escritorios de `escritorios/orden` con paquetes para `arch`, en ese orden (sobre las carpetas reales del repo: mismos escritorios que hoy).
7. Estado de un escritorio probado solo en `arch`: `probado` para `arch` y `experimental` para `debian-12`.

Pruebas 1–7: hechas.

Integración (se comprueba en el teléfono):

8. Hecha. Paquetes de Arch: los escritorios actuales declaran los suyos para `arch` y su estado probado para `arch`, sin cambiar ningún nombre. La prueba 6 y una instancia Arch nueva lo confirman.
9. Hecha. `primer-arranque.sh` arma el menú y la lista a instalar con las funciones de las pruebas 1–7.
10. Hecha (`pruebas/debian/paquetes.sh --repo <instancia>`, 58/58 en `deb12-paquetes-46743`, una Debian 12 `sin-entorno`). Prueba dentro de la app (`scripts/probar-en-telefono.sh`, solo lectura): cada paquete declarado en un `paquetes-debian-12.txt` existe según `apt-cache policy`. Ya está el perfil de Xfce (`xfce-x11`, X11 con `xfwm4`). La prueba cubre los 8 escritorios porque todos salen en el menú.
11. Hecha (sin commit). `deb12-xfce-71784` instalada, `salida=0`, transcripción en `files/pruebas/instalacion-deb12-xfce-71784.log`. El menú se comprueba con `pruebas/debian/menu.sh` dentro de la app (la creación sin pantalla no lo dibuja): los 8 de tasksel en orden, más la consola, todos experimentales.
    - Error encontrado: en Debian, `adduser` de los postinst (pulseaudio, polkitd, rtkit, colord) llama a `chfn`, que falla con "PAM: Authentication failure". dpkg deja los paquetes a medias y solo se arreglan con los reintentos de `backend_instalar` (9 → 3 → 0 en este caso, el último reintento). Pasa también en las instalaciones de GNOME y MATE de B11. Además, el aviso dice "Falló la descarga", y no lo era. Pendiente decidir el arreglo.
    Paso mínimo de interfaz: la instancia Debian 12 nueva se crea sin pantalla con `scripts/crear-en-telefono.sh` (de B11) eligiendo `xfce-x11`. El menú muestra los 8 de tasksel en su orden, más la consola, todos experimentales, y la instalación termina (con la transcripción en `files/pruebas/`).
12. XFCE arranca y se ve (captura con `grim`), y vuelve a arrancar tras cerrar y abrir la app. Entonces se marca `PROBADO_EN="debian-12"` en `xfce-x11/escritorio.conf`.
    - Si falla, es por Debian (paquetes, sesión, bus), no por la vía X11, que ya funciona desde B11. Parar y decidir antes de seguir.
