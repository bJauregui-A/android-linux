#!/usr/bin/bash
# B11: x11/compilar.sh produce libxserver.so y libxkbcomp.so en x11/salida/: ELF aarch64 para Android, cuyas
# bibliotecas necesarias (NEEDED) son solo las del sistema Android o las que van junto a ellos en el APK.
# 1a es libxkbcomp.so, 1b es libxserver.so.
# Corre en el PC:  pruebas/x11/compilacion.sh [xkbcomp|xserver]   (sin argumento, las dos)
cd "$(dirname "$0")/../.." || exit 1
export LC_ALL=C
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }

[ -x x11/compilar.sh ] || { echo "FALLA no existe x11/compilar.sh ejecutable"; exit 1; }
OBJETIVOS=${1:-xkbcomp xserver}
for o in $OBJETIVOS; do
  x11/compilar.sh $o >/tmp/x11-compilar-$o.log 2>&1 || { echo "FALLA x11/compilar.sh $o terminó con error (ver /tmp/x11-compilar-$o.log)"; exit 1; }
done

SISTEMA="libc.so libm.so libdl.so liblog.so libandroid.so libz.so"
necesarias() { readelf -d "$1" | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p'; }
for o in $OBJETIVOS; do
  lib=lib$o.so
  f=x11/salida/$lib
  caso "$lib existe"  "[ -f $f ]"
  caso "$lib es ELF aarch64 compartido"  "readelf -h $f | grep -q 'Machine:.*AArch64' && readelf -h $f | grep -q 'Type:.*DYN'"
  caso "$lib solo necesita bibliotecas de Android o del APK"  '
    ok=1
    for n in $(necesarias '$f'); do
      case " $SISTEMA " in *" $n "*) continue;; esac
      [ -f x11/salida/$n ] || { echo "      no resuelve: $n"; ok=0; }
    done
    [ $ok = 1 ]'
done

caso "todo lo de salida/ se llama lib<nombre>.so (jniLibs no extrae otros nombres)"  '
  ! ls x11/salida | grep -qvE "^lib[A-Za-z0-9_+-]+\.so$"'

# libX11 sin xlocale dejaba _Xi18n_lock sin definir y xkbcomp no enlazaba en el teléfono (CANNOT LINK EXECUTABLE)
[ -f x11/salida/libX11.so ] && caso "libX11.so no deja sin definir símbolos propios (_X*)"  '! nm -D --undefined-only x11/salida/libX11.so | grep -q " _X"'

echo "fallas: $fallas"
[ $fallas -eq 0 ]
