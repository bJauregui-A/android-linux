#!/bin/bash
# Copia compilar-wlroots.sh, el tarball y los parches de wlroots al Arch de la app.
# El tarball sale de trabajo/wlroots/ (bajarlo de gitlab.freedesktop.org/wlroots/wlroots/-/releases si falta).
# Después: TIEMPO=1200 scripts/correr.sh sdk36 scripts/test-compilar-wlroots.sh
set -e
cd "$(dirname "$0")/.."
PKG=dev.ben4shot.glibcprueba.sdk36
H=files/archlinux/home/user
adb shell "run-as $PKG mkdir -p $H/src/parches-wlroots"
adb shell "run-as $PKG sh -c 'rm -f $H/src/parches-wlroots/*.patch'"
copiar() { adb push "$1" /data/local/tmp/ >/dev/null
           adb shell "run-as $PKG cp /data/local/tmp/$(basename $1) $2 && rm /data/local/tmp/$(basename $1)"; }
copiar wlroots/compilar-wlroots.sh $H/
[ "$1" = sin-tarball ] || copiar trabajo/wlroots/wlroots-0.20.2.tar.gz $H/src/
for P in wlroots/parches/*.patch; do copiar $P $H/src/parches-wlroots/; done
