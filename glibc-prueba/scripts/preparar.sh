#!/bin/bash
# Baja paquetes base de Arch Linux ARM, arma un rootfs y lo instala en las apps de prueba.
# Uso: scripts/preparar.sh [carpeta-de-trabajo]   (requiere adb conectado y las apps instaladas)
set -e
W=${1:-/tmp/glibc-prueba-trabajo}; R=$W/rootfs; D=$W/dl; mkdir -p $R $D
PKGS='glibc|bash|readline|ncurses|gcc-libs|coreutils|acl|attr|gmp|libcap|openssl'
MIRROR=http://mirror.archlinuxarm.org/aarch64/core

# patchelf estático (no viene en Arch base)
P=$W/patchelf/bin/patchelf
if [ ! -x $P ]; then
  mkdir -p $W/patchelf && cd $W/patchelf
  URL=$(curl -sfL https://api.github.com/repos/NixOS/patchelf/releases/latest | grep -oE 'https://[^"]*x86_64\.tar\.gz' | head -1)
  curl -sfL "$URL" | tar -xz
fi

curl -sfL $MIRROR/ -o $D/index.html
for f in $(grep -oE "href=\"($PKGS)-[0-9][^\"]*\.pkg\.tar\.xz\"" $D/index.html | sed 's/href=//;s/"//g'); do
  [ -f $D/$f ] || curl -sfL "$MIRROR/$f" -o $D/$f
  tar -xJf $D/$f -C $R --exclude='.PKGINFO' --exclude='.BUILDINFO' --exclude='.MTREE' --exclude='.INSTALL' 2>/dev/null
done

HERE=$(cd "$(dirname "$0")" && pwd)
for v in sdk28 sdk36; do
  PKG=dev.ben4shot.glibcprueba.$v; F=/data/user/0/$PKG/files/glibc
  rm -rf $W/pkg-$v; mkdir -p $W/pkg-$v/glibc/pbin
  # binarios parcheados para probar exec directo de hijos (RPATH, no RUNPATH: debe ser transitivo)
  for b in bash ls cat; do
    cp $R/usr/bin/$b $W/pkg-$v/glibc/pbin/
    $P --set-interpreter $F/usr/lib/ld-linux-aarch64.so.1 --force-rpath --set-rpath $F/usr/lib $W/pkg-$v/glibc/pbin/$b
  done
  cp $HERE/test-bateria.sh $W/pkg-$v/test.sh
  # Android no permite enlaces duros: --hard-dereference los convierte en copias
  (cd $R && tar -cf $W/pkg-$v.tar --hard-dereference --transform 's,^\./,glibc/,' \
     --exclude='usr/share/locale' --exclude='usr/share/man' --exclude='usr/share/doc' \
     --exclude='usr/share/info' --exclude='usr/include' --exclude='usr/share/i18n' --exclude='*.a' .)
  (cd $W/pkg-$v && tar -rf $W/pkg-$v.tar glibc/pbin test.sh)
  adb push $W/pkg-$v.tar /data/local/tmp/pkg-$v.tar
  adb shell "run-as $PKG sh -c 'mkdir -p files && cd files && tar -xf /data/local/tmp/pkg-$v.tar && chmod 755 glibc/pbin/*'"
  adb shell rm /data/local/tmp/pkg-$v.tar
done
