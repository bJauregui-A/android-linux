#!/bin/bash
# Como correr.sh, pero con el anfitrión Wayland corriendo: abre el escritorio
# (WaylandActivity, que también arranca sway), corre el script en el mismo proceso
# (MainActivity, sin force-stop entre medio), vuelve al escritorio y saca una captura.
# Para probar clientes conectados directo al anfitrión:
#   WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR=/run/user/$(id -u) dentro del script.
# Uso: [ESPERA=s antes de la captura] [TIEMPO=s máx.] scripts/correr-wl.sh script.sh captura.png
set -e
PKG=dev.ben4shot.glibcprueba.sdk36
adb push "$1" /data/local/tmp/test.sh >/dev/null
adb shell "run-as $PKG cp /data/local/tmp/test.sh files/test.sh" && adb shell rm /data/local/tmp/test.sh
adb logcat -c; adb shell am force-stop $PKG
adb shell am start -W -n $PKG/dev.ben4shot.glibcprueba.WaylandActivity >/dev/null; sleep 1
adb shell am start -W -n $PKG/dev.ben4shot.glibcprueba.MainActivity >/dev/null; sleep 1
adb shell am start -W -n $PKG/dev.ben4shot.glibcprueba.WaylandActivity >/dev/null
sleep ${ESPERA:-12}; adb exec-out screencap -p > "$2"
for i in $(seq 1 $((${TIEMPO:-60} * 2))); do adb logcat -d -s 'GLIBC:*' | grep -q "=== fin" && break; sleep 0.5; done
adb logcat -d -s 'GLIBC:*' -v raw | grep -v '^---------'
