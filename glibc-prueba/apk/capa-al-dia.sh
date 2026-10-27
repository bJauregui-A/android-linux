#!/bin/bash
# El APK no se arma con una capa.tgz más vieja que sus fuentes (B23): las instancias recibirían una capa sin lo último
# del repo. Lo corre gradle (revisarCapa) antes de armar la variante sdk36.
#   apk/capa-al-dia.sh trabajo/assets-sdk36/capa.tgz
cd "$(dirname "$0")/.." || exit 1
C=$1
[ -f "$C" ] || { echo "falta $C: correr apk/armar.sh sdk36" >&2; exit 1; }
FUENTES="apk escritorios android sway supervisor mesa-gl scripts/adb-conectar glibc/salida/usr/lib
         trabajo/compilados.tar trabajo/libudmabuf-shim.so"
nuevos=$(for f in $FUENTES; do [ -e "$f" ] && echo "$f"; done |
         xargs -r -I{} find {} -newer "$C" -not -path '*/__pycache__*' -not -type d)
[ -z "$nuevos" ] && exit 0
{
    echo "$C es más vieja que sus fuentes; correr apk/armar.sh sdk36. Cambiaron:"
    echo "$nuevos" | sed 's/^/  /'
} >&2
exit 1
