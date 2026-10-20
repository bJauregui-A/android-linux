#!/bin/bash
# Copia compilar-mesa-gl.sh y los parches del GL de Mesa al Arch de la app, y los envoltorios
# con-gpu y firefox a /usr/local/bin (+ firefox.desktop propio que usa el envoltorio). No cierra nada.
# Compilar, desde kitty: bash ~/compilar-mesa-gl.sh > ~/mesa-gl.log 2>&1 &
set -e
cd "$(dirname "$0")/.."
PKG=dev.ben4shot.glibcprueba.sdk36
A=files/archlinux
H=$A/home/user
adb shell "run-as $PKG mkdir -p $H/src/parches-gl $A/usr/local/bin $H/.local/share/applications"
copiar() { adb push "$1" /data/local/tmp/ >/dev/null
           adb shell "run-as $PKG cp /data/local/tmp/$(basename $1) $2 && rm /data/local/tmp/$(basename $1)"; }
copiar mesa-gl/compilar-mesa-gl.sh $H/
for P in mesa-gl/parches/*.patch; do copiar $P $H/src/parches-gl/; done
copiar mesa-gl/con-gpu $A/usr/local/bin/
copiar mesa-gl/firefox $A/usr/local/bin/
adb shell "run-as $PKG chmod 755 $A/usr/local/bin/con-gpu $A/usr/local/bin/firefox"
# El .desktop de Arch llama a /usr/lib/firefox/firefox directo (se saltaría el envoltorio)
adb shell "run-as $PKG sh -c '[ ! -f $A/usr/share/applications/firefox.desktop ] ||
  sed \"s|/usr/lib/firefox/firefox|/usr/local/bin/firefox|\" $A/usr/share/applications/firefox.desktop > $H/.local/share/applications/firefox.desktop'"
echo "mesa-gl copiado"
