#!/bin/bash
# Copia compilar-mesa.sh, egl-zink.c y los parches de Mesa al Arch de la app.
# Después: TIEMPO=900 scripts/correr.sh sdk36 scripts/test-compilar-mesa.sh
set -e
cd "$(dirname "$0")/.."
PKG=dev.ben4shot.glibcprueba.sdk36
H=files/archlinux/home/user
adb shell "run-as $PKG mkdir -p $H/src/parches"
copiar() { adb push "$1" /data/local/tmp/ >/dev/null
           adb shell "run-as $PKG cp /data/local/tmp/$(basename $1) $2 && rm /data/local/tmp/$(basename $1)"; }
copiar turnip/compilar-mesa.sh $H/
copiar turnip/egl-zink.c $H/src/
for P in turnip/parches/*.patch; do copiar $P $H/src/parches/; done
