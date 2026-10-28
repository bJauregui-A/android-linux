#!/bin/bash
# B11: compila el servidor X11 y sus herramientas para Android aarch64 con el NDK (sin Docker).
# Uso: x11/compilar.sh [xkbcomp|xserver]      Resultado: x11/salida/libxkbcomp.so, libxserver.so
# xkbcomp se guarda con nombre de biblioteca: nativeLibraryDir es la única carpeta donde Android deja ejecutar.
set -euo pipefail
cd "$(dirname "$0")"
OBJETIVO=${1:-xkbcomp}
API=30
NDK=${ANDROID_NDK_HOME:-$HOME/Android/Sdk/ndk/28.2.13676358}
BIN=$(echo "$NDK"/toolchains/llvm/prebuilt/*/bin)
TRIPLE=aarch64-linux-android
RAIZ=$PWD
FUENTES=$RAIZ/fuentes; BUILD=$RAIZ/build; PREFIJO=$RAIZ/prefijo; SALIDA=$RAIZ/salida
mkdir -p "$FUENTES" "$BUILD" "$PREFIJO" "$SALIDA"

export PATH=$BIN:$PATH
export CC=${TRIPLE}${API}-clang CXX=${TRIPLE}${API}-clang++ AR=llvm-ar RANLIB=llvm-ranlib STRIP=llvm-strip
export CFLAGS="-O2 -fPIC -I$PREFIJO/include" LDFLAGS="-L$PREFIJO/lib"
export PKG_CONFIG_LIBDIR=$PREFIJO/lib/pkgconfig:$PREFIJO/share/pkgconfig PKG_CONFIG_PATH=
export ACLOCAL_PATH=$PREFIJO/share/aclocal
# Android no tiene libpthread (está en libc): un archivo vacío para los -lpthread de los .pc
[ -f "$PREFIJO/lib/libpthread.a" ] || { mkdir -p "$PREFIJO/lib"; llvm-ar rc "$PREFIJO/lib/libpthread.a"; }

# bajar <nombre-con-versión> <url-base>   deja fuentes/<nombre>/ sin parchear aparte de x11/parches/<nombre>*.patch
bajar() {
  local n=$1 url=$2 t
  [ -d "$FUENTES/$n" ] && return
  t=$(mktemp -d)
  curl -fL --retry 3 -o "$t/a" "$url/$n.tar.xz" || curl -fL --retry 3 -o "$t/a" "$url/$n.tar.gz"
  tar xf "$t/a" -C "$FUENTES"; rm -rf "$t"
  for p in "$RAIZ"/parches/"$n"*.patch; do [ -f "$p" ] && patch -d "$FUENTES/$n" -p1 < "$p"; done
  return 0
}

# autotools <nombre> <url> [opciones de configure]
autotools() {
  local n=$1 url=$2; shift 2
  [ -f "$BUILD/$n.listo" ] && return
  bajar "$n" "$url"
  mkdir -p "$BUILD/$n"; (cd "$BUILD/$n"
    ac_cv_func_malloc_0_nonnull=yes ac_cv_func_realloc_0_nonnull=yes xorg_cv_malloc0_returns_null=no "$FUENTES/$n/configure" --host=$TRIPLE --prefix="$PREFIJO" --disable-static --enable-shared \
      --disable-docs --disable-specs --without-doxygen "$@"
    make -j"$(nproc)"; make install)
  touch "$BUILD/$n.listo"
}

XORG=https://www.x.org/releases/individual
# copiar_necesarias <archivo>: copia a salida/ las lib*.so del prefijo que el archivo necesita, y las de ellas
copiar_necesarias() {
  local n
  for n in $(readelf -d "$1" | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p'); do
    if [ -f "$PREFIJO/lib/$n" ] && [ ! "$SALIDA/$n" -nt "$PREFIJO/lib/$n" ]; then
      cp -L "$PREFIJO/lib/$n" "$SALIDA/$n"; llvm-strip --strip-unneeded "$SALIDA/$n"
      copiar_necesarias "$SALIDA/$n"
    fi
  done
}

dependencias_xkbcomp() {
  autotools xorgproto-2024.1 $XORG/proto
  autotools xcb-proto-1.17.0 https://xcb.freedesktop.org/dist
  autotools libXau-1.0.11 $XORG/lib
  autotools libxcb-1.17.0 https://xcb.freedesktop.org/dist --disable-devel-docs --without-launchd
  autotools xtrans-1.5.2 $XORG/lib
  autotools libX11-1.8.10 $XORG/lib --disable-xcms --disable-loadable-i18n \
    --disable-ipv6 --disable-unix-transport --disable-local-transport --disable-tcp-transport
  autotools libxkbfile-1.1.3 $XORG/lib
}

# copiar_necesarias <archivo>: copia a salida/ las lib*.so del prefijo que el archivo necesita, y las de ellas
copiar_necesarias() {
  local n
  for n in $(readelf -d "$1" | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p'); do
    if [ -f "$PREFIJO/lib/$n" ] && [ ! "$SALIDA/$n" -nt "$PREFIJO/lib/$n" ]; then
      cp -L "$PREFIJO/lib/$n" "$SALIDA/$n"; llvm-strip --strip-unneeded "$SALIDA/$n"
      copiar_necesarias "$SALIDA/$n"
    fi
  done
}

xkbcomp() {
  dependencias_xkbcomp
  autotools xkbcomp-1.4.7 $XORG/app
  cp "$PREFIJO/bin/xkbcomp" "$SALIDA/libxkbcomp.so"
  llvm-strip --strip-unneeded "$SALIDA/libxkbcomp.so"
  copiar_necesarias "$SALIDA/libxkbcomp.so"
}

# meson <nombre> <url> [opciones]: compila e instala con un archivo de compilación cruzada.
# La marca .listo guarda las opciones con que se configuró: si cambian se vuelve a configurar. ninja corre siempre
# (es incremental).
meson_cruzado() {
  local n=$1 url=$2; shift 2
  if [ "$(cat "$BUILD/$n.listo" 2>/dev/null)" != "$*" ]; then
  bajar "$n" "$url"
  cat > "$BUILD/cruzado.ini" <<INI
[binaries]
c = '$BIN/${TRIPLE}${API}-clang'
cpp = '$BIN/${TRIPLE}${API}-clang++'
ar = '$BIN/llvm-ar'
strip = '$BIN/llvm-strip'
pkg-config = 'pkg-config'
[built-in options]
c_args = ['-O2', '-fPIC', '-I$PREFIJO/include']
c_link_args = ['-L$PREFIJO/lib']
pkg_config_path = ''
[properties]
needs_exe_wrapper = true
pkg_config_libdir = '$PREFIJO/lib/pkgconfig:$PREFIJO/share/pkgconfig'
[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
INI
  rm -rf "$BUILD/$n"
  meson setup "$BUILD/$n" "$FUENTES/$n" --cross-file "$BUILD/cruzado.ini" --prefix="$PREFIJO" --libdir=lib "$@"
  echo "$*" > "$BUILD/$n.listo"
  fi
  ninja -C "$BUILD/$n"; ninja -C "$BUILD/$n" install
}

dependencias_xserver() {
  dependencias_xkbcomp
  meson_cruzado pixman-0.43.4 https://cairographics.org/releases -Dgtk=disabled -Dlibpng=disabled -Dtests=disabled -Ddemos=disabled
  autotools libfontenc-1.1.8 $XORG/lib
  autotools libXfont2-2.0.7 $XORG/lib --disable-freetype --disable-bzip2 --disable-devel-docs --disable-fc --disable-pcfformat --disable-bdfformat
  autotools nettle-3.10 https://ftp.gnu.org/gnu/nettle --disable-shared --enable-static --enable-mini-gmp --disable-documentation --disable-assembler
  # B36: DRI3 necesita xshmfence (fences de Present; con futex y memfd, que bionic tiene) y drm_fourcc.h. Sin libdrm:
  # no hay nodo DRM, solo hacen falta los encabezados.
  autotools libxshmfence-1.3.2 $XORG/lib --enable-futex
  encabezados_drm
}

encabezados_drm() {
  local n=libdrm-2.4.124
  [ -f "$PREFIJO/include/drm_fourcc.h" ] && return
  bajar $n https://dri.freedesktop.org/libdrm
  mkdir -p "$PREFIJO/include"
  cp "$FUENTES/$n"/include/drm/{drm.h,drm_mode.h,drm_fourcc.h} "$PREFIJO/include/"
}

xserver() {
  dependencias_xserver
  local n=xorg-server-21.1.13
  bajar $n $XORG/xserver
  rm -rf "$FUENTES/$n/hw/android"; cp -r "$RAIZ/ddx/android" "$FUENTES/$n/hw/android"
  meson_cruzado $n $XORG/xserver \
    -Dlisten_tcp=false -Dlisten_local=false -Dlisten_unix=true -Dmitshm=false \
    -Dglx=false -Ddri1=false -Ddri2=false -Ddri3=true -Dglamor=false \
    -Dxorg=false -Dxephyr=false -Dxnest=false -Dxvfb=false -Dxwin=false -Dxquartz=false \
    -Dudev=false -Dudev_kms=false -Dhal=false -Dsystemd_logind=false -Dxdmcp=false -Dint10=false -Dsecure-rpc=false \
    -Dxdm-auth-1=false -Dxcsecurity=false -Dxselinux=false -Dsha1=libnettle -Ddocs=false -Ddevel-docs=false \
    -Dipv6=false -Dpciaccess=false -Ddrm=false -Dxf86-input-inputtest=false -Dxkb_default_layout=latam \
    -Dxkb_dir=/data/xkb -Dxkb_bin_dir=/data/bin -Ddefault_font_path=built-ins
  cp "$BUILD/$n/hw/android/libxserver.so" "$SALIDA/libxserver.so"
  llvm-strip --strip-unneeded "$SALIDA/libxserver.so"
  copiar_necesarias "$SALIDA/libxserver.so"
}

# Datos de teclado (xkeyboard-config): no dependen de la arquitectura, se generan con el meson del PC.
# Van a assets/xkb/ (assets del APK); el servidor los lee con -xkbdir, no los toma de la distro.
xkb() {
  local n=xkeyboard-config-2.43 t
  bajar $n $XORG/data/xkeyboard-config
  rm -rf "$BUILD/$n" "$RAIZ/assets/xkb"
  meson setup "$BUILD/$n" "$FUENTES/$n" --prefix=/usr -Dnls=false -Dcompat-rules=false -Dxorg-rules-symlinks=false
  t=$(mktemp -d)
  DESTDIR=$t meson install -C "$BUILD/$n" >/dev/null
  mkdir -p "$RAIZ/assets/xkb"
  for d in keycodes types compat symbols rules; do cp -r "$t/usr/share/X11/xkb/$d" "$RAIZ/assets/xkb/$d"; done
  # el servidor pide xkb_geometry { include "pc" }; solo ese archivo (el resto de geometry son teclados concretos)
  mkdir -p "$RAIZ/assets/xkb/geometry"; cp "$t/usr/share/X11/xkb/geometry/pc" "$RAIZ/assets/xkb/geometry/pc"
  rm -rf "$t"
}

case $OBJETIVO in
  xkbcomp) xkbcomp ;;
  xserver) xserver ;;
  xkb) xkb ;;
  *) echo "objetivo desconocido: $OBJETIVO"; exit 2 ;;
esac
