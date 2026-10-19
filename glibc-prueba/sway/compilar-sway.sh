#!/usr/bin/bash
# Compila sway 1.12 con parches propios dentro del Arch de la app, contra el wlroots
# parchado de ~/wlroots (wlroots/compilar-wlroots.sh: necesita el 0004, escala de contenido).
# scripts/subir-sway-parchado.sh lo copia a ~/ junto con ~/src/sway-1.12.tar.gz y ~/src/parches-sway/.
#   0001: una ventana cuyo tamaño mínimo no cabe en su espacio se dibuja achicada en vez
#         de recortada (apps de escritorio en la pantalla del teléfono)
#   0002: `xwayland_scale <n>` (config): Xwayland ve la pantalla en píxeles reales y sway
#         dibuja las ventanas X11 divididas por n (nítidas con la salida a escala 2.5)
#   0003: una ventana flotante más grande que la pantalla (diálogos de escritorio) se achica
#         manteniendo proporciones y se centra, como 0001 hace con las de mosaico
#   0004: comando `scale_to_fit enable` (solo Xwayland): la ventana conserva el tamaño que pide
#         y se dibuja agrandada/achicada para llenar su contenedor (juegos en un escritorio de Wine fijo)
# Resultado en ~/sway/bin/sway; TerminalService lo prefiere al de Arch si existe.
set -e
V=1.12
cd ~/src
[ -d sway-$V ] || tar xzf sway-$V.tar.gz
cd sway-$V
for P in ~/src/parches-sway/*.patch; do
  [ -e "$P" ] || continue
  [ -f .aplicado-$(basename $P) ] && continue
  git apply "$P" && touch .aplicado-$(basename $P)
done
GLIBC_FAKEROOT=1 pacman -S --needed --noconfirm meson ninja wayland-protocols json-c pcre2 2>&1 | tail -3
export PKG_CONFIG_PATH=$HOME/wlroots/lib/pkgconfig
[ -d build ] || meson setup build --prefix=$HOME/sway --buildtype=release \
  -Dman-pages=disabled -Dzsh-completions=false -Dfish-completions=false \
  -Dbash-completions=false -Dwerror=false
time ninja -C build
ninja -C build install
echo "=== sway listo"
