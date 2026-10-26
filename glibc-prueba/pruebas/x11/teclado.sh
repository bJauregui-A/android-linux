#!/usr/bin/bash
# B11: con los datos de xkeyboard-config que van en el APK (x11/assets/xkb/), el xkbcomp del PC compila el
# mapa evdev con distribución latam sin errores, y solo vienen las carpetas que usa el servidor.
# "-I" sin carpeta borra las rutas del sistema: así la prueba solo ve nuestros datos (con las del PC, una
# carpeta que falta en el APK pasaba desapercibida y en el teléfono xkbcomp no encontraba geometry/pc).
# Corre en el PC:  pruebas/x11/teclado.sh
cd "$(dirname "$0")/../.." || exit 1
export LC_ALL=C
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }

x11/compilar.sh xkb >/tmp/x11-compilar-xkb.log 2>&1 || { echo "FALLA x11/compilar.sh xkb terminó con error (ver /tmp/x11-compilar-xkb.log)"; exit 1; }
X=$PWD/x11/assets/xkb
d=$(mktemp -d); trap 'rm -rf "$d"' EXIT

caso "solo compat, geometry, keycodes, rules, symbols y types"  "[ \"\$(ls $X | tr '\n' ' ')\" = 'compat geometry keycodes rules symbols types ' ]"
caso "de geometry solo viene pc"  "[ \"\$(ls $X/geometry)\" = pc ]"
caso "hay rules/evdev"  "[ -f $X/rules/evdev ]"
caso "setxkbmap resuelve evdev+latam con esos datos"  \
  "setxkbmap -I -I$X -rules evdev -model pc105 -layout latam -print > $d/latam.xkb 2>$d/err && grep -q latam $d/latam.xkb"
caso "xkbcomp compila el mapa sin errores"  \
  "xkbcomp -I -I$X -xkm $d/latam.xkb $d/latam.xkm 2>$d/err2; ! grep -qi '^Error' $d/err2 && [ -s $d/latam.xkm ]"

echo "fallas: $fallas"
[ $fallas -eq 0 ]
