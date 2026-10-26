#!/usr/bin/bash
# B67: menu_escritorios de apk/primer-arranque.sh da los escritorios del menú: los de escritorios/orden-$DISTRO,
# en ese orden, que tengan carpeta, sesion y paquetes-$DISTRO.txt; la consola (sin-entorno) siempre aparece.
# Corre en el PC, sobre carpetas temporales:  pruebas/escritorios/menu.sh
cd "$(dirname "$0")/../.." || exit 1
eval "$(sed -n '/^menu_escritorios() {/,/^}/p' apk/primer-arranque.sh)"
type menu_escritorios >/dev/null 2>&1 || { echo "FALLA no se encontró menu_escritorios"; exit 1; }
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }
d=$(mktemp -d); trap 'rm -rf "$d"' EXIT
ED=$d/escritorios; mkdir -p $ED/xfce-x11 $ED/kde $ED/lxqt $ED/sin-entorno

# Debian 12: orden de tasksel; sin carpeta (gnome) o sin paquetes para debian-12 (kde) no aparece.
printf '# tasksel\ngnome\nxfce-x11\nkde\nlxqt\nsin-entorno\n' > $ED/orden-debian-12
touch $ED/xfce-x11/sesion $ED/lxqt/sesion $ED/kde/sesion
touch $ED/xfce-x11/paquetes-debian-12.txt $ED/lxqt/paquetes-debian-12.txt $ED/kde/paquetes-arch.txt
DISTRO=debian-12
caso "debian-12: los que tienen paquetes, en orden, y la consola"  '[ "$(menu_escritorios | tr "\n" " ")" = "xfce-x11 lxqt sin-entorno " ]'

# Con paquetes pero sin sesión (aún no se puede arrancar): no aparece.
mkdir -p $ED/sin-sesion; printf 'xfce-x11\nsin-sesion\nsin-entorno\n' > $ED/orden-debian-13
touch $ED/xfce-x11/paquetes-debian-13.txt $ED/sin-sesion/paquetes-debian-13.txt
DISTRO=debian-13
caso "debian-13: sin sesión no aparece"  '[ "$(menu_escritorios | tr "\n" " ")" = "xfce-x11 sin-entorno " ]'

# Arch: los mismos escritorios que hoy, en el mismo orden, sobre las carpetas reales del repo.
ED=escritorios DISTRO=arch
caso "arch: los de siempre, en su orden"  '[ "$(menu_escritorios | tr "\n" " ")" = "sway hyprland labwc xfce lxqt kde plasma-movil phosh niri cosmic wayfire river qtile weston sin-entorno " ]'

echo "fallas: $fallas"
[ $fallas -eq 0 ]
