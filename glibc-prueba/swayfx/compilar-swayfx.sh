#!/usr/bin/bash
# Compila swayfx 0.6 (sway con efectos: bordes redondeados, sombras, desenfoque)
# dentro del Arch de la app. Usa scenefx 0.5 de Arch (renderer GLES2) y wlroots0.20.
# scripts/subir-swayfx.sh lo copia a ~/ junto con ~/src/swayfx-0.6.tar.gz.
# Resultado en ~/swayfx/bin/sway (no reemplaza al sway de Arch).
set -e
V=0.6
cd ~/src
[ -d swayfx-$V ] || tar xzf swayfx-$V.tar.gz
cd swayfx-$V
GLIBC_FAKEROOT=1 pacman -S --needed --noconfirm scenefx meson ninja wayland-protocols json-c pcre2 2>&1 | tail -3
[ -d build ] || meson setup build --prefix=$HOME/swayfx --buildtype=release \
  -Dman-pages=disabled -Dzsh-completions=false -Dfish-completions=false \
  -Dbash-completions=false -Dwerror=false
time ninja -C build
ninja -C build install
echo "=== swayfx listo"
