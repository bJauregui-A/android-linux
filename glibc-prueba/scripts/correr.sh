#!/bin/bash
# Copia un script de prueba a la app, la abre y muestra la salida (logcat tag GLIBC).
# Uso: [TIEMPO=segundos] scripts/correr.sh sdk36|sdk28 scripts/test-bateria.sh
set -e
PKG=dev.ben4shot.glibcprueba.$1
adb push "$2" /data/local/tmp/test.sh >/dev/null
adb shell "run-as $PKG cp /data/local/tmp/test.sh files/test.sh" && adb shell rm /data/local/tmp/test.sh
adb logcat -c; adb shell am force-stop $PKG
adb shell am start -W -n $PKG/dev.ben4shot.glibcprueba.MainActivity >/dev/null
for i in $(seq 1 $((${TIEMPO:-15} * 2))); do adb logcat -d -s 'GLIBC:*' | grep -q "=== fin\|error" && break; sleep 0.5; done
adb logcat -d -s 'GLIBC:*' -v raw | grep -v '^---------'
