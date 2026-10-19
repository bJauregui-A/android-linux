#!/bin/bash
# Copia steam/proton-directo al Steam del teléfono (no cierra nada).
# Steam ve las herramientas nuevas al reiniciarse.
set -e
cd "$(dirname "$0")"
PKG=dev.ben4shot.glibcprueba.sdk36
D=files/archlinux/home/user/.local/share/Steam/compatibilitytools.d/proton-directo
adb shell "run-as $PKG mkdir -p $D"
for f in compatibilitytool.vdf toolmanifest.vdf proton; do
  adb push proton-directo/$f /data/local/tmp/$f >/dev/null
  adb shell "run-as $PKG sh -c 'cat /data/local/tmp/$f > $D/$f; chmod 755 $D/$f'"
  adb shell rm /data/local/tmp/$f
done
echo "instalado en ~/.local/share/Steam/compatibilitytools.d/proton-directo"
