#!/usr/bin/bash
# Compila wlroots 0.20.2 con parches propios dentro del Arch de la app (como Mesa).
# scripts/subir-wlroots.sh lo copia a ~/ junto con ~/src/wlroots-0.20.2.tar.gz y ~/src/parches-wlroots/.
#   0001: renderer Vulkan sin nodo DRM (Turnip con KGSL)
#   0002: allocator android-ahb-v1 en el backend wayland (sway compone directo en el AHardwareBuffer)
#   0003: linux-dmabuf sin nodo DRM (v3, sin feedback): los clientes de sway le pasan dmabufs
# Resultado en ~/wlroots/lib/libwlroots-0.20.so; sway lo usa con LD_LIBRARY_PATH=~/wlroots/lib.
set -e
V=0.20.2
cd ~/src
[ -d wlroots-$V ] || tar xzf wlroots-$V.tar.gz
cd wlroots-$V
for P in ~/src/parches-wlroots/*.patch; do
  [ -e "$P" ] || continue
  [ -f .aplicado-$(basename $P) ] && continue
  git apply "$P" && touch .aplicado-$(basename $P)
done
# Dependencias de compilación (las de ejecución ya vienen con sway)
GLIBC_FAKEROOT=1 pacman -S --needed --noconfirm meson ninja glslang vulkan-headers wayland-protocols xorg-xwayland 2>&1 | tail -3
# Opciones por defecto, como el paquete de Arch: sway se enlaza con -z now y necesita
# los mismos símbolos (xwayland, drm, libinput, session...).
[ -d build ] || meson setup build --prefix=$HOME/wlroots --buildtype=debugoptimized \
  -Dexamples=false -Dwerror=false
time ninja -C build
ninja -C build install
# Símbolos: los de Arch tienen que estar todos en la nuestra
nm -D --defined-only /usr/lib/libwlroots-0.20.so | awk '{print $3}' | sort > /tmp/sim-arch.txt
nm -D --defined-only $HOME/wlroots/lib/libwlroots-0.20.so | awk '{print $3}' | sort > /tmp/sim-nueva.txt
faltan=$(comm -23 /tmp/sim-arch.txt /tmp/sim-nueva.txt)
[ -z "$faltan" ] && echo "símbolos: ok" || { echo "faltan símbolos:"; echo "$faltan"; }
echo "=== wlroots listo"
