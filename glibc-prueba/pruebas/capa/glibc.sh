#!/usr/bin/bash
# B23: al actualizar, la glibc nueva de la capa (usr/local/share/linux-android/glibc/) reemplaza solo los archivos que
# la instancia ya tiene en usr/lib y, en Debian, en usr/lib/aarch64-linux-gnu. Antes se respalda la que había en
# $E/glibc-anterior/ (uno solo); si un intento anterior quedó cortado (marca actualizando) se conserva ese respaldo.
# Corre en el PC con raíces de mentira:  pruebas/capa/glibc.sh
cd "$(dirname "$0")/../.." || exit 1
eval "$(sed -n '/^respaldar_glibc() {/,/^}/p; /^instalar_glibc() {/,/^}/p' apk/instalar.sh)"
type instalar_glibc >/dev/null 2>&1 || { echo "FALLA no se encontró instalar_glibc en apk/instalar.sh"; exit 1; }
type respaldar_glibc >/dev/null 2>&1 || { echo "FALLA no se encontró respaldar_glibc en apk/instalar.sh"; exit 1; }
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
G=usr/local/share/linux-android/glibc
A=var/lib/linux-android

# raíz <dir> <libs de la instancia...>: glibc vieja instalada y la nueva en la capa ya extraída
raiz() {
    local r=$1; shift
    mkdir -p "$r/$G" "$r/$A" "$r/usr/lib"
    for f in libc.so.6 libm.so.6 libnsl.so.1; do echo "nueva $f" > "$r/$G/$f"; done
    for f in "$@"; do mkdir -p "$r/$(dirname "$f")"; echo "vieja $(basename "$f")" > "$r/$f"; done
}

R=$T/arch; raiz "$R" usr/lib/libc.so.6 usr/lib/libm.so.6
instalar_glibc "$R"
caso "Arch: reemplaza libc.so.6 en usr/lib"  'grep -qx "nueva libc.so.6" "$R/usr/lib/libc.so.6"'
caso "Arch: reemplaza libm.so.6 en usr/lib"  'grep -qx "nueva libm.so.6" "$R/usr/lib/libm.so.6"'
caso "Arch: no crea usr/lib/aarch64-linux-gnu"  '[ ! -e "$R/usr/lib/aarch64-linux-gnu" ]'
caso "Arch: no quedan .nuevo"  '[ -z "$(find "$R/usr/lib" -name "*.nuevo")" ]'

R=$T/debian; raiz "$R" usr/lib/libc.so.6 usr/lib/libm.so.6 usr/lib/aarch64-linux-gnu/libc.so.6 usr/lib/aarch64-linux-gnu/libm.so.6
instalar_glibc "$R"
for d in usr/lib usr/lib/aarch64-linux-gnu; do
    caso "Debian: reemplaza libc.so.6 en $d"  'grep -qx "nueva libc.so.6" "$R/$d/libc.so.6"'
    caso "Debian: reemplaza libm.so.6 en $d"  'grep -qx "nueva libm.so.6" "$R/$d/libm.so.6"'
done

caso "un archivo que la instancia no tiene no se agrega"  \
  '[ ! -e "$T/arch/usr/lib/libnsl.so.1" ] && [ ! -e "$T/debian/usr/lib/aarch64-linux-gnu/libnsl.so.1" ]'

R=$T/respaldo; raiz "$R" usr/lib/libc.so.6 usr/lib/libm.so.6
mkdir -p "$R/$A/glibc-anterior"; echo "más vieja" > "$R/$A/glibc-anterior/libc.so.6"; echo x > "$R/$A/glibc-anterior/libviejo.so.1"
respaldar_glibc "$R"
caso "sin marca: el respaldo es la glibc que había"  'grep -qx "vieja libc.so.6" "$R/$A/glibc-anterior/libc.so.6"'
caso "sin marca: no se acumulan respaldos anteriores"  '[ ! -e "$R/$A/glibc-anterior/libviejo.so.1" ]'

R=$T/cortado; raiz "$R" usr/lib/libc.so.6
mkdir -p "$R/$A/glibc-anterior"; echo "la de antes del corte" > "$R/$A/glibc-anterior/libc.so.6"; touch "$R/$A/actualizando"
respaldar_glibc "$R"
caso "con marca actualizando: se conserva el respaldo previo"  \
  'grep -qx "la de antes del corte" "$R/$A/glibc-anterior/libc.so.6"'

echo "fallas: $fallas"
[ $fallas -eq 0 ]
