#!/bin/bash
# Regenera app/.../Distribucion.java desde el keymap de xkbcommon del PC.
# Uso: wayland/generar-teclado.sh [distribución, por defecto latam]
# La misma distribución tiene que ir en ~/.config/sway/config (xkb_layout).
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
cc -O2 -o build/generar-teclado generar-teclado.c $(pkg-config --cflags --libs xkbcommon)
build/generar-teclado "${1:-latam}" > ../app/src/main/java/dev/ben4shot/glibcprueba/Distribucion.java
echo "Distribucion.java: ${1:-latam}"
