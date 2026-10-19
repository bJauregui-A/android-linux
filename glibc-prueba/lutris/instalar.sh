#!/bin/bash
# Deja el Wine de Proton 11 ARM64 como versión "proton-11-arm64" del runner Wine de Lutris (no cierra nada).
# Lutris la ve al volver a abrirse.
set -e
cd "$(dirname "$0")"
PKG=dev.ben4shot.glibcprueba.sdk36
L=files/archlinux/home/user/.local/share/lutris
W=$L/runners/wine/proton-11-arm64
P='/home/user/.local/share/Steam/steamapps/common/Proton 11.0 (ARM64)/files'
copiar() { adb push "$1" /data/local/tmp/lutris-$1 >/dev/null
           adb shell "run-as $PKG sh -c 'cat /data/local/tmp/lutris-$1 > $2'"; adb shell rm /data/local/tmp/lutris-$1; }
adb shell "run-as $PKG mkdir -p $W/bin"
copiar wine $W/bin/wine
adb shell "run-as $PKG sh -c 'chmod 755 $W/bin/wine; cd $W; ln -sfn \"$P/lib\" lib; ln -sfn \"$P/share\" share; ln -sfn \"$P/bin-arm64/wineserver\" bin/wineserver; ln -sfn \"$P/bin-arm64/msidb\" bin/msidb'"
copiar wine.yml $L/runners/wine.yml
copiar system.yml $L/system.yml
echo "instalado: Lutris → runner Wine, versión proton-11-arm64"
