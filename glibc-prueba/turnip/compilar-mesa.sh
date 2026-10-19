#!/usr/bin/bash
# Compila Mesa (solo Turnip, backend KGSL) dentro del Arch de la app.
# Se copia a ~/compilar-mesa.sh (y egl-zink.c y parches/ a ~/src) y se corre desde la terminal de la app:
#   bash ~/compilar-mesa.sh > ~/mesa.log 2>&1 &
# Resultado en ~/turnip; usar con VK_ICD_FILENAMES=~/turnip/share/vulkan/icd.d/freedreno_icd.aarch64.json
set -e
V=26.2.5
cd ~/src
[ -d mesa-$V ] || tar xf mesa-$V.tar.xz
cd mesa-$V
# Parches propios (0001: WSI de Wayland con buffers del anfitrión, cero copias)
for P in ~/src/parches/*.patch; do
  [ -e "$P" ] || continue
  [ -f .aplicado-$(basename $P) ] && continue
  git apply "$P" && touch .aplicado-$(basename $P)
done
# kmds=kgsl,msm: msm no se usa (no hay /dev/dri), pero sin él Mesa deja fuera
# libdrm y la WSI no puede presentar por dmabuf (solo por CPU, MESA_VK_WSI_DEBUG=sw).
# debugoptimized: con aserciones y líneas para gdb.
[ -d build ] || meson setup build --prefix=$HOME/turnip --buildtype=debugoptimized \
  -Dplatforms=wayland -Dvulkan-drivers=freedreno -Dfreedreno-kmds=kgsl,msm \
  -Dgallium-drivers= -Dopengl=false -Dglx=disabled -Degl=disabled -Dgles1=disabled -Dgles2=disabled \
  -Dgbm=disabled -Dllvm=disabled -Dvideo-codecs= -Dvalgrind=disabled -Dlibunwind=disabled -Dlmsensors=disabled
time ninja -C build
ninja -C build install
# OpenGL: Zink (del mesa de Arch) sobre este Turnip; ver egl-zink.c
gcc -O2 -shared -fPIC -o $HOME/turnip/lib/libegl-zink.so ~/src/egl-zink.c
echo "=== mesa listo"
