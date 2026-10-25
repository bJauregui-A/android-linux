#!/bin/bash
# Corre B26 en el teléfono con la libc nueva (copiada en files/prueba-libc).
# Dentro de una instancia: bash /tmp/rz.sh   (solo lectura)
D=/data/user/0/dev.ben4shot.glibcprueba.sdk36/files/prueba-libc
[ -f $D/libc.so.6 ] || { echo "no encuentro $D/libc.so.6"; exit 1; }
echo "== con la libc instalada:"; ls /.. | head -3
echo "== con la libc nueva:";     LD_LIBRARY_PATH=$D ls /.. | head -3
echo "== C20b /sdcard/.. vieja vs nueva (mismo contexto):"
v=$(ls /sdcard/.. 2>&1 | head -5); n=$(LD_LIBRARY_PATH=$D ls /sdcard/.. 2>&1 | head -5)
[ "$v" = "$n" ] && echo "OK    C20b igual en las dos" || { echo "FALLA C20b"; echo "  vieja: $v"; echo "  nueva: $n"; }
if [ "$1" = vieja ]; then
  echo "== en-telefono.sh con la libc INSTALADA (rojo esperado):"
  bash $D/en-telefono.sh
else
  echo "== en-telefono.sh con la libc nueva:"
  LD_LIBRARY_PATH=$D bash $D/en-telefono.sh
fi
