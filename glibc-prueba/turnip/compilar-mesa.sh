#!/usr/bin/bash
# Compila Mesa (solo Turnip, backend KGSL) dentro del Arch de la app.
# Se copia a ~/compilar-mesa.sh y se corre desde la terminal de la app:
#   bash ~/compilar-mesa.sh > ~/mesa.log 2>&1 &
# Resultado en ~/turnip; usar con VK_ICD_FILENAMES=~/turnip/share/vulkan/icd.d/freedreno_icd.aarch64.json
set -e
V=26.2.5
cd ~/src
[ -d mesa-$V ] || tar xf mesa-$V.tar.xz
cd mesa-$V
[ -d build ] || meson setup build --prefix=$HOME/turnip --buildtype=release \
  -Dplatforms=wayland -Dvulkan-drivers=freedreno -Dfreedreno-kmds=kgsl \
  -Dgallium-drivers= -Dopengl=false -Dglx=disabled -Degl=disabled -Dgles1=disabled -Dgles2=disabled \
  -Dgbm=disabled -Dllvm=disabled -Dvideo-codecs= -Dvalgrind=disabled -Dlibunwind=disabled -Dlmsensors=disabled
time ninja -C build
ninja -C build install
echo "=== mesa listo"
