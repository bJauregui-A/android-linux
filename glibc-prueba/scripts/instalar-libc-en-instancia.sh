#!/bin/bash
# Instala glibc/salida en UNA instancia ya existente, sin recompilar ni reinstalar la APK.
#   scripts/instalar-libc-en-instancia.sh <instancia>            instala (con respaldo)
#   scripts/instalar-libc-en-instancia.sh <instancia> --revertir  vuelve a lo respaldado
# Solo reemplaza archivos que la instancia ya tiene (en usr/lib o usr/lib/aarch64-linux-gnu).
# Respaldo: files/respaldos-glibc/<instancia>/ y libc.so.6.00NN junto a la libc.
# Reemplaza con mv (atómico): los procesos que ya la usan siguen con la anterior.
APP=${APP:-dev.ben4shot.glibcprueba.sdk36}
inst=$1; modo=$2
[ -n "$inst" ] || { echo "uso: $0 <instancia> [--revertir]"; exit 2; }
cd "$(dirname "$0")/../glibc/salida/usr/lib" || exit 1
T=/data/local/tmp/glibc-nueva
if [ "$modo" != --revertir ]; then
  adb shell "rm -rf $T; mkdir -p $T" || exit 1
  for f in $(ls | grep -E '\.so(\.[0-9]+)+$|^ld-linux'); do adb push "$f" $T/ >/dev/null || exit 1; done
fi
adb shell "run-as $APP sh -s" "$inst" "$modo" <<'REMOTO'
inst=$1; modo=$2; T=/data/local/tmp/glibc-nueva
R=files/instancias/$inst; B=files/respaldos-glibc/$inst
[ -d $R ] || { echo "no existe la instancia $inst"; exit 1; }
if [ "$modo" = --revertir ]; then
  [ -d $B ] || { echo "no hay respaldo en $B"; exit 1; }
  for d in usr/lib usr/lib/aarch64-linux-gnu; do
    for f in $(ls $B/$(echo $d | tr / _) 2>/dev/null); do cp -p $B/$(echo $d | tr / _)/$f $R/$d/$f.nuevo && mv -f $R/$d/$f.nuevo $R/$d/$f && echo "revertido $d/$f"; done
  done; exit 0
fi
n=0
for src in $T/*; do
  f=$(basename $src)
  for d in usr/lib usr/lib/aarch64-linux-gnu; do
    [ -f $R/$d/$f ] && [ ! -L $R/$d/$f ] || continue
    mkdir -p $B/$(echo $d | tr / _)
    [ -f $B/$(echo $d | tr / _)/$f ] || cp -p $R/$d/$f $B/$(echo $d | tr / _)/$f      # respaldo (el primero se conserva)
    if [ $f = libc.so.6 ]; then
      i=1; while [ -e $R/$d/libc.so.6.$(printf %04d $i) ]; do i=$((i+1)); done
      cp -p $R/$d/$f $R/$d/libc.so.6.$(printf %04d $i)
    fi
    cp $src $R/$d/$f.nuevo && chmod 755 $R/$d/$f.nuevo && mv -f $R/$d/$f.nuevo $R/$d/$f && echo "instalado $d/$f" && n=$((n+1))
  done
done
echo "$n archivos instalados en $inst"
REMOTO
[ "$modo" != --revertir ] && adb shell "rm -rf $T"
