#!/bin/bash
# Arma los assets del APK autoinstalable en trabajo/assets-<variante>/ (gradle los mete solos):
#   base.tgz  Arch ARM mínimo (pacman + dependencias) con la glibc propia (scripts/bootstrap.py)
#   capa.tgz  lo compilado en el teléfono (trabajo/compilados.tar) + configs + instalador (apk/capa.py)
#   instalar.sh  primer arranque (lo corre la app en la terminal)
# Los enlaces absolutos llevan la ruta del prefijo, así que es por variante (paquete).
# Requisitos: glibc/salida (glibc/compilar.sh) y trabajo/compilados.tar (apk/traer-compilados.sh).
#   apk/armar.sh [sdk36]  &&  ./gradlew assembleSdk36Debug
set -e
cd "$(dirname "$0")/.."
V=${1:-sdk36}
PKG=dev.ben4shot.glibcprueba.$V
PREFIJO=/data/user/0/$PKG/files/archlinux
OUT=trabajo/assets-$V
[ -f trabajo/compilados.tar ] || { echo "falta trabajo/compilados.tar: apk/traer-compilados.sh"; exit 1; }
mkdir -p $OUT
Z=gzip; command -v pigz > /dev/null && Z=pigz
python3 scripts/bootstrap.py --prefix $PREFIJO --glibc glibc/salida/usr/lib --out trabajo/base-$V.tar pacman
if [ ! -f "$OUT/base-debian.tgz" ] || [ "${REHACER_DEBIAN:-0}" = "1" ]; then
    echo "==> Generando base de Debian ARM64..."
    python3 scripts/bootstrap-debian.py --prefix $PREFIJO --glibc glibc/salida/usr/lib --out trabajo/base-debian-$V.tar
    $Z -9 -c trabajo/base-debian-$V.tar > $OUT/base-debian.tgz
    rm trabajo/base-debian-$V.tar
fi
python3 apk/capa.py --prefix $PREFIJO --compilados trabajo/compilados.tar --out trabajo/capa-$V.tar
$Z -9 -c trabajo/base-$V.tar > $OUT/base.tgz
$Z -9 -c trabajo/capa-$V.tar > $OUT/capa.tgz
rm trabajo/base-$V.tar trabajo/capa-$V.tar
cp apk/instalar.sh $OUT/
cp glibc/salida/usr/lib/ld-linux-aarch64.so.1 app/src/main/jniLibs/arm64-v8a/libldp.so
du -h $OUT/*
