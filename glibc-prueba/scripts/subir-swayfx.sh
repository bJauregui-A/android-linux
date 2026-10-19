#!/bin/bash
# Copia compilar-swayfx.sh y el tarball de swayfx al Arch de la app.
# El tarball sale de trabajo/swayfx/ (github.com/WillPower3309/swayfx/archive/refs/tags/0.6.tar.gz).
# Después: TIEMPO=900 scripts/correr.sh sdk36 scripts/test-compilar-swayfx.sh
set -e
cd "$(dirname "$0")/.."
PKG=dev.ben4shot.glibcprueba.sdk36
H=files/archlinux/home/user
copiar() { adb push "$1" /data/local/tmp/ >/dev/null
           adb shell "run-as $PKG cp /data/local/tmp/$(basename $1) $2 && rm /data/local/tmp/$(basename $1)"; }
copiar swayfx/compilar-swayfx.sh $H/
[ "$1" = sin-tarball ] || copiar trabajo/swayfx/swayfx-0.6.tar.gz $H/src/
