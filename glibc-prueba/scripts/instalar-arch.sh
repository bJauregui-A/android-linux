#!/bin/bash
# Instala Arch Linux ARM con pacman en la app de prueba (prefijo files/archlinux)
# y corre el primer arranque (usuario, scripts post_install, llavero de pacman).
# Uso: scripts/instalar-arch.sh [sdk36|sdk28]
set -e
V=${1:-sdk36}; PKG=dev.ben4shot.glibcprueba.$V
cd "$(dirname "$0")/.."
mkdir -p trabajo
python3 scripts/bootstrap.py --prefix /data/user/0/$PKG/files/archlinux \
  --glibc glibc/salida/usr/lib --out trabajo/archlinux-$V.tar
cp glibc/salida/usr/lib/ld-linux-aarch64.so.1 app/src/main/jniLibs/arm64-v8a/libldp.so
./gradlew -q assemble${V^}Debug
adb install -r app/build/outputs/apk/$V/debug/app-$V-debug.apk >/dev/null
adb shell "run-as $PKG mkdir -p files/archlinux"
adb shell "run-as $PKG tar -xf - -C files/archlinux" < trabajo/archlinux-$V.tar
TIEMPO=300 scripts/correr.sh $V scripts/arch-inicio.sh
