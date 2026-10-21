#!/usr/bin/bash
# Compila Mesa (solo Turnip, backend KGSL) dentro del Arch de la app.
# Se copia a ~/compilar-mesa.sh (y egl-zink.c y parches/ a ~/src) y se corre desde la terminal de la app:
#   bash ~/compilar-mesa.sh > ~/mesa.log 2>&1 &
# Resultado en ~/turnip (o en $PREFIX); usar con VK_ICD_FILENAMES=~/turnip/share/vulkan/icd.d/freedreno_icd.aarch64.json
set -e
V=26.2.5
PREFIX=${PREFIX:-$HOME/turnip}
# build-x11: con la plataforma x11 (Wine usa winex11 → DXVK pide VK_KHR_xlib_surface)
B=build-x11
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
[ -d $B ] || meson setup $B --prefix=$PREFIX --buildtype=debugoptimized \
  -Dplatforms=wayland,x11 -Dvulkan-drivers=freedreno -Dfreedreno-kmds=kgsl,msm \
  -Dgallium-drivers= -Dopengl=false -Dglx=disabled -Degl=disabled -Dgles1=disabled -Dgles2=disabled \
  -Dgbm=disabled -Dllvm=disabled -Dvideo-codecs= -Dvalgrind=disabled -Dlibunwind=disabled -Dlmsensors=disabled
time ninja -C $B
ninja -C $B install
# OpenGL: Zink (del mesa de Arch) sobre este Turnip; ver egl-zink.c y udmabuf-shim.c
gcc -O2 -shared -fPIC -o $PREFIX/lib/libegl-zink.so ~/src/egl-zink.c
[ -f ~/src/udmabuf-shim.c ] && gcc -O2 -shared -fPIC -o /usr/local/lib/libudmabuf-shim.so ~/src/udmabuf-shim.c -ldl
echo "=== mesa listo"
