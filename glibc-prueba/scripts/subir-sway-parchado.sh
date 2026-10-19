#!/bin/bash
# Copia sway/compilar-sway.sh, el tarball y los parches de sway al Arch de la app.
# El tarball sale de trabajo/sway/ (github.com/swaywm/sway/releases/download/1.12/sway-1.12.tar.gz).
# Después compilar sin cerrar nada (el sway abierto sigue con sus bibliotecas en memoria):
#   scripts/compilar-en-fondo.sh compilar-wlroots.sh   (si cambió algún parche de wlroots)
#   scripts/compilar-en-fondo.sh compilar-sway.sh
set -e
cd "$(dirname "$0")/.."
PKG=dev.ben4shot.glibcprueba.sdk36
H=files/archlinux/home/user
adb shell "run-as $PKG mkdir -p $H/src/parches-sway"
adb shell "run-as $PKG sh -c 'rm -f $H/src/parches-sway/*.patch'"
copiar() { adb push "$1" /data/local/tmp/ >/dev/null
           adb shell "run-as $PKG cp /data/local/tmp/$(basename $1) $2 && rm /data/local/tmp/$(basename $1)"; }
copiar sway/compilar-sway.sh $H/
[ "$1" = sin-tarball ] || copiar trabajo/sway/sway-1.12.tar.gz $H/src/
for P in sway/parches/*.patch; do copiar $P $H/src/parches-sway/; done
