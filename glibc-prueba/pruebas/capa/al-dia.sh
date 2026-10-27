#!/usr/bin/bash
# B23: el build se niega a armar el APK con una capa.tgz más vieja que sus fuentes (si no, las instancias recibirían
# una capa que no tiene lo último del repo). Corre en el PC con un árbol de mentira:  pruebas/capa/al-dia.sh
cd "$(dirname "$0")/../.." || exit 1
[ -f apk/capa-al-dia.sh ] || { echo "FALLA no existe apk/capa-al-dia.sh"; exit 1; }
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

mkdir -p "$T/apk" "$T/escritorios/xfce" "$T/android" "$T/sway" "$T/supervisor" "$T/mesa-gl" "$T/scripts" \
         "$T/glibc/salida/usr/lib" "$T/trabajo/assets-sdk36"
cp apk/capa-al-dia.sh "$T/apk/"
for f in apk/primer-arranque.sh escritorios/xfce/instalar android/android-abrir sway/config supervisor/service \
         mesa-gl/con-gpu scripts/adb-conectar glibc/salida/usr/lib/libc.so.6 trabajo/compilados.tar \
         trabajo/libudmabuf-shim.so; do
    echo x > "$T/$f"
done
find "$T" -type f -exec touch -d '2026-01-01' {} +
C=$T/trabajo/assets-sdk36/capa.tgz
echo capa > "$C"; touch -d '2026-02-01' "$C"

"$T/apk/capa-al-dia.sh" "$C" > "$T/salida" 2>&1; rc=$?
caso "todas las fuentes más viejas que capa.tgz: sale con 0"  '[ $rc -eq 0 ]'

touch -d '2026-03-01' "$T/apk/primer-arranque.sh"
"$T/apk/capa-al-dia.sh" "$C" > "$T/salida" 2>&1; rc=$?
caso "un archivo de apk/ más nuevo: sale con error"  '[ $rc -ne 0 ]'
caso "un archivo de apk/ más nuevo: lo nombra"  'grep -q "apk/primer-arranque.sh" "$T/salida"'
caso "un archivo de apk/ más nuevo: dice cómo rehacerla"  'grep -qF "apk/armar.sh sdk36" "$T/salida"'
touch -d '2026-01-01' "$T/apk/primer-arranque.sh"

touch -d '2026-03-01' "$T/glibc/salida/usr/lib/libc.so.6"
"$T/apk/capa-al-dia.sh" "$C" > "$T/salida" 2>&1; rc=$?
caso "una glibc más nueva: sale con error y la nombra"  '[ $rc -ne 0 ] && grep -q "glibc/salida/usr/lib/libc.so.6" "$T/salida"'
touch -d '2026-01-01' "$T/glibc/salida/usr/lib/libc.so.6"

rm "$C"
"$T/apk/capa-al-dia.sh" "$C" > "$T/salida" 2>&1; rc=$?
caso "sin capa.tgz: sale con error"  '[ $rc -ne 0 ]'

echo "fallas: $fallas"
[ $fallas -eq 0 ]
