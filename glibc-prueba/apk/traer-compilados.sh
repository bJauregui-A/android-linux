#!/bin/bash
# Trae del teléfono lo compilado ahí (no está en el repo, solo sus scripts y parches) a
# trabajo/compilados.tar, para meterlo en el APK (apk/armar.sh). Solo lee: no cierra nada.
#   ~/wlroots ~/sway ~/turnip ~/turnip-x11 ~/mesa-gl (sin include/) y /opt/gtk2 (sin include/)
# Volver a correrlo después de recompilar algo de eso en el teléfono.
#   apk/traer-compilados.sh [sdk36]
# files/archlinux ya no existe en los teléfonos con instancias (sin él, sin --de falla sin tocar nada): con --de se reemplazan solo esos componentes del
# compilados.tar que ya hay, tomándolos de una instancia (compilados con prefijo /home/user/<nombre>: capa.py solo
# reescribe /home/user/ → /usr/local/).
#   apk/traer-compilados.sh sdk36 --de <instancia> <nombre>...     p. ej.  --de arch-debian-38075 turnip-x11
set -e
cd "$(dirname "$0")/.."
PKG=dev.ben4shot.glibcprueba.${1:-sdk36}
mkdir -p trabajo
if [ "$2" = --de ]; then
  inst=$3; shift 3
  [ -n "$inst" ] && [ $# -gt 0 ] && [ -f trabajo/compilados.tar ] || { echo "uso: $0 sdk36 --de <instancia> <nombre>... (necesita trabajo/compilados.tar)" >&2; exit 2; }
  t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
  tar -C "$t" -xf trabajo/compilados.tar
  for n in "$@"; do rm -rf "${t:?}/home/user/$n"; done
  rutas=$(printf 'home/user/%s ' "$@")
  adb exec-out "run-as $PKG sh -c 'cd files/instancias/$inst && tar -cf - --exclude=include $rutas'" | tar -C "$t" -xf -
  for n in "$@"; do [ -d "$t/home/user/$n" ] || { echo "no llegó home/user/$n de $inst" >&2; exit 1; }; done
  tar -C "$t" -cf trabajo/compilados.tar.part $(cd "$t" && ls -d home/user/* opt 2>/dev/null)
  mv trabajo/compilados.tar.part trabajo/compilados.tar
  echo "trabajo/compilados.tar: $(du -h trabajo/compilados.tar | cut -f1) ($* de $inst)"
  exit 0
fi
if [ "$(adb exec-out "run-as $PKG sh -c '[ -d files/archlinux ] && echo si'")" != si ]; then
  echo "el teléfono no tiene files/archlinux (lo compilado vive en las instancias): usar" >&2
  echo "  $0 ${1:-sdk36} --de <instancia> <nombre>...     p. ej.  --de arch-debian-38075 turnip-x11" >&2
  exit 1
fi
adb exec-out "run-as $PKG sh -c 'cd files/archlinux && tar -cf - --exclude=include \
  home/user/wlroots home/user/sway home/user/turnip home/user/turnip-x11 home/user/mesa-gl opt/gtk2'" \
  > trabajo/compilados.tar.part
tar -tf trabajo/compilados.tar.part > /dev/null  # que esté entero
mv trabajo/compilados.tar.part trabajo/compilados.tar
echo "trabajo/compilados.tar: $(du -h trabajo/compilados.tar | cut -f1)"
