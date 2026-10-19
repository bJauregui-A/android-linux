#!/bin/bash
# Compila libffi y libwayland-server para Android arm64 (bionic, NDK) como
# bibliotecas estáticas para el anfitrión Wayland de la app (app/src/main/cpp).
# Resultado: wayland/salida/{include,lib}. Usa wayland-scanner del PC.
set -euo pipefail
cd "$(dirname "$0")"
NDK=${NDK:-$HOME/Android/Sdk/ndk/28.2.13676358}
TC=$NDK/toolchains/llvm/prebuilt/linux-x86_64
API=31
FFI=3.5.2
WL=1.26.0
OUT=$PWD/salida
mkdir -p fuentes build "$OUT"

[ -f fuentes/libffi-$FFI.tar.gz ] || curl -fL -o fuentes/libffi-$FFI.tar.gz \
  https://github.com/libffi/libffi/releases/download/v$FFI/libffi-$FFI.tar.gz
[ -f fuentes/wayland-$WL.tar.xz ] || curl -fL -o fuentes/wayland-$WL.tar.xz \
  https://gitlab.freedesktop.org/wayland/wayland/-/releases/$WL/downloads/wayland-$WL.tar.xz

export CC=$TC/bin/aarch64-linux-android$API-clang
export AR=$TC/bin/llvm-ar RANLIB=$TC/bin/llvm-ranlib STRIP=$TC/bin/llvm-strip
export CFLAGS="-O2 -fPIC"

# libffi (autotools)
if [ ! -f "$OUT/lib/libffi.a" ]; then
  rm -rf build/libffi-$FFI && tar xf fuentes/libffi-$FFI.tar.gz -C build
  (cd build/libffi-$FFI && ./configure --host=aarch64-linux-android --prefix="$OUT" \
     --disable-shared --enable-static --disable-docs --disable-multi-os-directory -q \
   && make -j"$(nproc)" -s && make install -s)
fi

# libwayland-server (meson, cruzado)
cat > build/android.cross <<EOF
[binaries]
c = '$CC'
ar = '$AR'
strip = '$STRIP'
pkg-config = 'pkg-config'

[properties]
pkg_config_libdir = '$OUT/lib/pkgconfig'

[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
EOF
if [ ! -f "$OUT/lib/libwayland-server.a" ]; then
  rm -rf build/wayland-$WL build/wl && tar xf fuentes/wayland-$WL.tar.xz -C build
  meson setup build/wl build/wayland-$WL --cross-file build/android.cross \
    --prefix="$OUT" --libdir=lib --default-library=static --buildtype=release \
    -Dlibraries=true -Dscanner=false -Dtests=false -Ddocumentation=false -Ddtd_validation=false
  ninja -C build/wl install
fi
# Código de servidor de los protocolos extra (xdg-shell, linux-dmabuf)
mkdir -p "$OUT/proto"
for X in stable/xdg-shell/xdg-shell stable/linux-dmabuf/linux-dmabuf-v1; do
  N=$(basename $X)
  wayland-scanner server-header /usr/share/wayland-protocols/$X.xml "$OUT/proto/$N-server-protocol.h"
  wayland-scanner private-code /usr/share/wayland-protocols/$X.xml "$OUT/proto/$N-protocol.c"
done
ls -la "$OUT/lib/"*.a "$OUT/proto"
