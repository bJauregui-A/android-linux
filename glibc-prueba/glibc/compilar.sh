#!/bin/bash
# Compila la glibc parchada para aarch64 dentro de Docker (no instala nada en el PC).
# Resultado: glibc/salida/ (árbol /usr de la glibc, listo para copiar al prefijo).
set -euo pipefail
cd "$(dirname "$0")"
VER=2.43
docker build -q -t glibc-cross .
[ -f glibc-$VER.tar.xz ] || curl -fLO https://ftp.gnu.org/gnu/glibc/glibc-$VER.tar.xz
if [ ! -d glibc-$VER ]; then
  tar xf glibc-$VER.tar.xz
  for p in parches/*.patch; do patch -d glibc-$VER -p1 < "$p"; done
fi
mkdir -p build salida
docker run --rm -u "$(id -u):$(id -g)" -v "$PWD:/w" -w /w/build glibc-cross bash -c "
  set -e
  if [ ! -f config.status ]; then
    ../glibc-$VER/configure --host=aarch64-linux-gnu --build=x86_64-pc-linux-gnu \
      --prefix=/usr --libdir=/usr/lib --libexecdir=/usr/lib \
      --with-headers=/usr/aarch64-linux-gnu/include \
      --enable-bind-now --enable-fortify-source --enable-stack-protector=strong \
      --enable-multi-arch --enable-kernel=4.4 --disable-profile --disable-werror --disable-crypt
  fi
  printf 'slibdir=/usr/lib\nrtlddir=/usr/lib\nsbindir=/usr/bin\nrootsbindir=/usr/bin\n' > configparms
  make -j\$(nproc)
  rm -rf ../salida/*
  make install DESTDIR=/w/salida
"
ls salida/usr/lib/ld-linux-aarch64.so.1 salida/usr/lib/libc.so.6
