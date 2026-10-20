#!/bin/bash
# Trae del teléfono lo compilado ahí (no está en el repo, solo sus scripts y parches) a
# trabajo/compilados.tar, para meterlo en el APK (apk/armar.sh). Solo lee: no cierra nada.
#   ~/wlroots ~/sway ~/turnip ~/turnip-x11 ~/mesa-gl (sin include/) y /opt/gtk2 (sin include/)
# Volver a correrlo después de recompilar algo de eso en el teléfono.
#   apk/traer-compilados.sh [sdk36]
set -e
cd "$(dirname "$0")/.."
PKG=dev.ben4shot.glibcprueba.${1:-sdk36}
mkdir -p trabajo
adb exec-out "run-as $PKG sh -c 'cd files/archlinux && tar -cf - --exclude=include \
  home/user/wlroots home/user/sway home/user/turnip home/user/turnip-x11 home/user/mesa-gl opt/gtk2'" \
  > trabajo/compilados.tar.part
tar -tf trabajo/compilados.tar.part > /dev/null  # que esté entero
mv trabajo/compilados.tar.part trabajo/compilados.tar
echo "trabajo/compilados.tar: $(du -h trabajo/compilados.tar | cut -f1)"
