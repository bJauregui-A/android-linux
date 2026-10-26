# B67 · Menú de Debian 12 como tasksel, paquetes por distro y versión, y XFCE funcionando

Como usuario de Debian 12, quiero que el menú muestre los escritorios que ofrece su instalador (tasksel) con los paquetes de Debian 12, y tener XFCE probado y funcionando, para elegir como en una instalación real.

Deja el mecanismo para las demás distros (B65 Arch, B68 Debian 13, B69/B70 Ubuntu).

Estado de partida (25-oct):
- El menú (`apk/primer-arranque.sh`, `escritorios/orden`) es el mismo para todas las distros.
- Los paquetes de cada escritorio salen de `escritorios/<id>/paquetes.txt` (nombres de Arch) o de `paquetes-<backend>.txt`, que nadie tiene. Debian usó los nombres de Arch y la instalación de XFCE abortó: `labwc`, `xfdesktop`, `garcon` y `exo` no existen en bookworm (comprobado con `apt-cache policy` en `debian_desktop-74818`).
- `ESTADO=probado` vale para todas las distros.
- `/etc/os-release`: Arch ARM trae `ID=archarm`, `ID_LIKE=arch` y no trae `VERSION_ID` (rolling). Debian trae `ID=debian` y `VERSION_ID="12"`.

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
   - Al terminar esta historia, eso es: Xfce (X11, con `xfwm4`, como lo instala Debian) y consola. Los demás aparecen solos cuando se les declaren paquetes (B73–B78 y siguientes).

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
- Los demás escritorios de tasksel (GNOME, Flashback, KDE Plasma, Cinnamon, MATE, LXDE, LXQt) en Debian 12: no se les declaran paquetes aquí, así que no aparecen.
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

Integración (se comprueba en el teléfono):

8. Paquetes de Arch: los escritorios actuales declaran los suyos para `arch` y su estado probado para `arch`, sin cambiar ningún nombre. La prueba 6 y una instancia Arch nueva lo confirman.
9. `primer-arranque.sh` arma el menú y la lista a instalar con las funciones de las pruebas 1–7.
10. Xfce para `debian-12`: perfil X11 con `xfwm4` y sus paquetes de Debian 12. Prueba dentro de la app (`scripts/probar-en-telefono.sh`, solo lectura): cada paquete declarado para `debian-12` existe según `apt-cache policy`.
11. Paso mínimo de interfaz: el menú de una Debian 12 nueva muestra Xfce (experimental) y consola, y la instalación termina.
12. XFCE arranca y se ve (captura con `grim`), y vuelve a arrancar tras cerrar y abrir la app. Entonces se marca probado en `debian-12`.
    - Riesgo: la vía X11 directa (B11) no está validada. Si falla aquí, parar y decidir antes de seguir.

Al cerrar: actualizar `TECNICO.md` (cómo se declaran los paquetes y el estado por distro y versión, y el menú por instalador).
