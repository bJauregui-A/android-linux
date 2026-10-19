#!/bin/bash
# Regenera app/.../Distribucion.java y app/src/main/cpp/keymap.h desde el keymap de xkbcommon del PC.
# Uso: wayland/generar-teclado.sh [distribución, por defecto latam]
# La misma distribución tiene que ir en ~/.config/sway/config (xkb_layout).
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
cc -O2 -o build/generar-teclado generar-teclado.c $(pkg-config --cflags --libs xkbcommon)
build/generar-teclado "${1:-latam}" > ../app/src/main/java/dev/ben4shot/glibcprueba/Distribucion.java
# El mismo keymap, como texto, para los clientes conectados directo al anfitrión.
{ echo "/* Generado por wayland/generar-teclado.sh: keymap xkb ${1:-latam}.  */"
  echo "static const char keymap_xkb[] ="
  xkbcli compile-keymap --layout "${1:-latam}" | sed 's/\\/\\\\/g; s/"/\\"/g; s/.*/  "&\\n"/'
  echo ";"; } > ../app/src/main/cpp/keymap.h
echo "Distribucion.java y keymap.h: ${1:-latam}"
