#!/usr/bin/bash
# Compila el OpenGL de Mesa (EGL + GLX + Zink) dentro del Arch de la app, en un prefijo aparte.
# No reemplaza al mesa de Arch: solo lo usa quien tenga LD_LIBRARY_PATH=~/mesa-gl/lib
# (glvnd carga libEGL_mesa.so.0 / libGLX_mesa.so.0 por nombre).
# Se copia a ~/compilar-mesa-gl.sh (y parches/ a ~/src/parches-gl) y se corre desde la terminal de la app:
#   bash ~/compilar-mesa-gl.sh > ~/mesa-gl.log 2>&1 &
# Parche 0001: Zink bajo drisw (sin kopper) lee el cuadro y lo entrega con put_image (antes: ventanas negras).
set -e
V=26.2.5
PREFIX=${PREFIX:-$HOME/mesa-gl}
B=build-gl
cd ~/src
[ -d mesa-$V ] || tar xf mesa-$V.tar.xz
cd mesa-$V
for P in ~/src/parches-gl/*.patch; do
  [ -e "$P" ] || continue
  [ -f .aplicado-gl-$(basename $P) ] && continue
  git apply "$P" && touch .aplicado-gl-$(basename $P)
done
# softpipe: respaldo por CPU si Zink no arranca (sin LLVM no hay llvmpipe).
[ -d $B ] || meson setup $B --prefix=$PREFIX --buildtype=release -Db_ndebug=true \
  -Dplatforms=wayland,x11 -Dvulkan-drivers= -Dgallium-drivers=zink,softpipe \
  -Dopengl=true -Dglx=dri -Degl=enabled -Dgles1=disabled -Dgles2=enabled -Dglvnd=enabled \
  -Dgbm=disabled -Dllvm=disabled -Dgallium-va=disabled -Dgallium-rusticl=false -Dvideo-codecs= \
  -Dvalgrind=disabled -Dlibunwind=disabled -Dlmsensors=disabled -Dbuild-tests=false
time ninja -C $B
ninja -C $B install
echo "=== mesa-gl listo"
