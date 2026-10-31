#!/usr/bin/bash
# B96: apk/migraciones/002-carpetas-de-root.sh deja /tmp y /var/tmp en 1777 y, en Debian, trae /mnt y /media (como la base nueva).
# Corre en el PC sobre un árbol de mentira (MIGRAR_RAIZ):  pruebas/capa/migracion-tmp.sh
cd "$(dirname "$0")/../.." || exit 1
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
M=$PWD/apk/migraciones/002-carpetas-de-root.sh
[ -f "$M" ] || { echo "FALLA no existe $M"; exit 1; }
modo() { stat -c %a "$1"; }
correr() { MIGRAR_RAIZ=$1 bash "$M" >"$1.salida" 2>&1; }

D=$T/debian; mkdir -p "$D/tmp" "$D/var/tmp" "$D/usr/bin" "$D/home"; : > "$D/usr/bin/apt-get"
chmod 755 "$D/tmp" "$D/var/tmp"
correr "$D"; rc=$?
caso "Debian: sale con 0"  '[ $rc -eq 0 ]'
caso "Debian: /tmp pasa a 1777"  '[ "$(modo $D/tmp)" = 1777 ]'
caso "Debian: /var/tmp pasa a 1777"  '[ "$(modo $D/var/tmp)" = 1777 ]'
caso "Debian: crea /mnt de 755"  '[ "$(modo $D/mnt)" = 755 ]'
caso "Debian: crea /media de 755"  '[ "$(modo $D/media)" = 755 ]'
chmod 700 "$D/mnt"; correr "$D"; rc=$?
caso "segunda corrida: sale con 0 y no toca un /mnt existente"  '[ $rc -eq 0 ] && [ "$(modo $D/mnt)" = 700 ]'
caso "segunda corrida: /tmp sigue 1777"  '[ "$(modo $D/tmp)" = 1777 ]'

A=$T/arch; mkdir -p "$A/tmp" "$A/var/tmp" "$A/mnt"; chmod 1777 "$A/tmp"; chmod 755 "$A/var/tmp"
correr "$A"; rc=$?
caso "Arch: sale con 0"  '[ $rc -eq 0 ]'
caso "Arch: /var/tmp pasa a 1777"  '[ "$(modo $A/var/tmp)" = 1777 ]'
caso "Arch: no crea /media"  '[ ! -e "$A/media" ]'

V=$T/vacia; mkdir -p "$V"
correr "$V"; rc=$?
caso "sin /tmp ni /var/tmp no falla ni los crea"  '[ $rc -eq 0 ] && [ ! -e "$V/tmp" ]'
echo "fallas: $fallas"
exit $fallas
