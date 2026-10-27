#!/usr/bin/bash
# B11: los siete escritorios X11 (proveedor x11-directo) salen en el menú de su distro, sin probar: Arch con
# Openbox y XFCE X11; Debian 12 con Xfce, GNOME, GNOME Flashback, Cinnamon, MATE y LXDE. Ninguno probado en Arch;
# Xfce probado en debian-12 (B67, prueba 12), los demás experimentales.
# Corre en el PC, sobre las carpetas reales del repo:  pruebas/escritorios/x11.sh
cd "$(dirname "$0")/../.." || exit 1
eval "$(sed -n '/^menu_escritorios() {/,/^}/p;/^estado_escritorio() {/,/^}/p' apk/primer-arranque.sh)"
type menu_escritorios >/dev/null 2>&1 && type estado_escritorio >/dev/null 2>&1 || { echo "FALLA no se encontraron las funciones de apk/primer-arranque.sh"; exit 1; }
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }
ED=escritorios

X11="openbox xfce-x11 gnome gnome-flashback cinnamon mate lxde"
for e in $X11; do
  caso "$e: proveedor x11-directo y sin probar en arch"  \
    "( . $ED/$e/escritorio.conf; [ \"\$PROVEEDOR_PANTALLA\" = x11-directo ] && [[ \" \$PROBADO_EN \" != *' arch '* ]] )"
done

DISTRO=arch
caso "orden-arch incluye openbox y xfce-x11"  'grep -qx openbox $ED/orden-arch && grep -qx xfce-x11 $ED/orden-arch'
menu=" $(menu_escritorios | tr '\n' ' ')"
for e in openbox xfce-x11; do
  caso "arch: el menú trae $e, experimental"  '[[ "$menu" == *" $e "* ]] && [ "$(estado_escritorio $e)" = experimental ]'
done

DISTRO=debian-12
menu=" $(menu_escritorios | tr '\n' ' ')"
caso "debian-12: el menú trae xfce-x11, probado"  '[[ "$menu" == *" xfce-x11 "* ]] && [ "$(estado_escritorio xfce-x11)" = probado ]'
for e in gnome gnome-flashback cinnamon mate lxde; do
  caso "debian-12: el menú trae $e, experimental"  '[[ "$menu" == *" $e "* ]] && [ "$(estado_escritorio $e)" = experimental ]'
done

# openbox-session corre openbox-xdg-autostart, que sin PyXDG termina con "requires PyXDG to be installed" y
# deja sin arrancar lo que haya en ~/.config/autostart y /etc/xdg/autostart.
caso "openbox (arch) trae python-pyxdg"  'grep -qx python-pyxdg $ED/openbox/paquetes-arch.txt'

# Sin DISPLAY heredado, las recetas usan el display propio (:10), no el :0 del Xwayland.
for e in $X11; do
  caso "$e: DISPLAY por defecto :10"  'grep -q "DISPLAY:-:10}" $ED/$e/sesion && ! grep -q "DISPLAY:-:0}" $ED/$e/sesion'
done

# xfce4-session lanza ssh-agent y gpg-agent, que se marcan no volcables: con /proc en hidepid=invisible la app no
# los ve, así que ni la pausa ni el cierre del escritorio los alcanzan y quedan huérfanos. La receta los apaga antes.
for a in ssh-agent gpg-agent; do
  caso "xfce-x11: apaga $a de xfce4-session antes de startxfce4"  \
    "sed -n '1,/startxfce4/p' $ED/xfce-x11/sesion | grep -q 'xfconf-query -c xfce4-session -p /startup/$a/enabled -n -t bool -s false'"
done

echo "fallas: $fallas"
[ $fallas -eq 0 ]
