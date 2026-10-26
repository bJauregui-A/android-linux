#!/usr/bin/bash
# B11: los siete escritorios X11 (proveedor x11-directo) salen en el menú de su distro, sin probar: Arch con
# Openbox y XFCE X11; Debian 12 con Xfce, GNOME, GNOME Flashback, Cinnamon, MATE y LXDE; PROBADO_EN vacío.
# Corre en el PC, sobre las carpetas reales del repo:  pruebas/escritorios/x11.sh
cd "$(dirname "$0")/../.." || exit 1
eval "$(sed -n '/^menu_escritorios() {/,/^}/p;/^estado_escritorio() {/,/^}/p' apk/primer-arranque.sh)"
type menu_escritorios >/dev/null 2>&1 && type estado_escritorio >/dev/null 2>&1 || { echo "FALLA no se encontraron las funciones de apk/primer-arranque.sh"; exit 1; }
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }
ED=escritorios

X11="openbox xfce-x11 gnome gnome-flashback cinnamon mate lxde"
for e in $X11; do
  caso "$e: proveedor x11-directo y PROBADO_EN vacío"  \
    "( . $ED/$e/escritorio.conf; [ \"\$PROVEEDOR_PANTALLA\" = x11-directo ] && [ -z \"\$PROBADO_EN\" ] )"
done

DISTRO=arch
caso "orden-arch incluye openbox y xfce-x11"  'grep -qx openbox $ED/orden-arch && grep -qx xfce-x11 $ED/orden-arch'
menu=" $(menu_escritorios | tr '\n' ' ')"
for e in openbox xfce-x11; do
  caso "arch: el menú trae $e, experimental"  '[[ "$menu" == *" $e "* ]] && [ "$(estado_escritorio $e)" = experimental ]'
done

DISTRO=debian-12
menu=" $(menu_escritorios | tr '\n' ' ')"
for e in xfce-x11 gnome gnome-flashback cinnamon mate lxde; do
  caso "debian-12: el menú trae $e, experimental"  '[[ "$menu" == *" $e "* ]] && [ "$(estado_escritorio $e)" = experimental ]'
done

echo "fallas: $fallas"
[ $fallas -eq 0 ]
