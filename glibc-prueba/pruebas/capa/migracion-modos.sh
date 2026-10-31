#!/usr/bin/bash
# B96: apk/migraciones/001-modos-de-linux.sh deja con modo de Linux lo que los procesos de la app crearon con umask 077.
# Corre en el PC sobre un árbol de mentira (MIGRAR_RAIZ):  pruebas/capa/migracion-modos.sh
cd "$(dirname "$0")/../.." || exit 1
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
M=$PWD/apk/migraciones/001-modos-de-linux.sh
[ -f "$M" ] || { echo "FALLA no existe $M"; exit 1; }
modo() { stat -c %a "$T/$1"; }
mkdir -p "$T/etc" "$T/usr/local/turnip/lib" "$T/usr/local/turnip-x11/lib" "$T/usr/local/sway/bin" "$T/usr/local/otro"
cd "$T" || exit 1
for f in etc/resolv.conf etc/hostname etc/hosts etc/virtual-ip etc/shadow etc/gshadow; do echo x > $f; chmod 600 $f; done
echo x > etc/hosts-propio; chmod 640 etc/hosts-propio
: > usr/local/turnip/lib/libegl-zink.so; chmod 700 usr/local/turnip/lib/libegl-zink.so
: > usr/local/turnip-x11/lib/libegl-zink.so; chmod 700 usr/local/turnip-x11/lib/libegl-zink.so
: > usr/local/sway/bin/sway; chmod 700 usr/local/sway/bin/sway
: > usr/local/otro/privado; chmod 600 usr/local/otro/privado
cd - >/dev/null || exit 1
correr() { MIGRAR_RAIZ=$T bash "$M" >"$T.salida" 2>&1; }
correr; rc=$?
caso "sale con 0"  '[ $rc -eq 0 ]'
for f in etc/resolv.conf etc/hostname etc/hosts etc/virtual-ip; do
  caso "$f de 600 a 644"  '[ "$(modo $f)" = 644 ]'
done
caso "etc/shadow sigue 600"  '[ "$(modo etc/shadow)" = 600 ]'
caso "etc/gshadow sigue 600"  '[ "$(modo etc/gshadow)" = 600 ]'
caso "un archivo de /etc con otro modo no se toca"  '[ "$(modo etc/hosts-propio)" = 640 ]'
caso "la biblioteca de turnip de 700 a 755"  '[ "$(modo usr/local/turnip/lib/libegl-zink.so)" = 755 ]'
caso "la de turnip-x11 de 700 a 755"  '[ "$(modo usr/local/turnip-x11/lib/libegl-zink.so)" = 755 ]'
caso "lo compilado de sway de 700 a 755"  '[ "$(modo usr/local/sway/bin/sway)" = 755 ]'
caso "lo que no es de la app en usr/local no se toca"  '[ "$(modo usr/local/otro/privado)" = 600 ]'
chmod 600 "$T/etc/hosts"; chmod 664 "$T/etc/hostname"
correr; rc=$?
caso "segunda corrida: sale con 0"  '[ $rc -eq 0 ]'
caso "segunda corrida: vuelve a arreglar un 600"  '[ "$(modo etc/hosts)" = 644 ]'
caso "segunda corrida: un 664 no se toca"  '[ "$(modo etc/hostname)" = 664 ]'
rm -rf "$T/etc" "$T/usr"
correr; rc=$?
caso "sin los archivos no falla"  '[ $rc -eq 0 ]'
echo "fallas: $fallas"
exit $fallas
