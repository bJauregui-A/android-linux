#!/bin/bash
# Copia el cliente de prueba de cero copias y el código de cliente de los
# protocolos (generado por wayland/compilar.sh) a ~/src/ahb del Arch de la app.
set -e
cd "$(dirname "$0")/.."
PKG=dev.ben4shot.glibcprueba.sdk36
D=files/archlinux/home/user/src/ahb
adb shell "run-as $PKG mkdir -p $D"
for F in turnip/prueba-ahb.c wayland/salida/proto/{xdg-shell,android-ahb-v1}-{protocol.c,client-protocol.h}; do
  adb push "$F" /data/local/tmp/ >/dev/null
  adb shell "run-as $PKG cp /data/local/tmp/$(basename $F) $D/ && rm /data/local/tmp/$(basename $F)"
done
