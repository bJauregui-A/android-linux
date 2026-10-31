#!/usr/bin/bash
# B96: el primer arranque normaliza los modos de las carpetas del sistema a 755 (avisos de pacman), pero no puede quitarle el
# sticky a /tmp ni /var/tmp (1777). Corre en el PC sobre un árbol de mentira:  pruebas/capa/primer-arranque-modos.sh
cd "$(dirname "$0")/../.." || exit 1
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
linea=$(grep -F 'find /usr /etc /var /opt -maxdepth 3 -type d' apk/primer-arranque.sh)
[ -n "$linea" ] || { echo "FALLA no se encontró la línea de normalizar modos en apk/primer-arranque.sh"; exit 1; }
mkdir -p "$T/usr/lib/x" "$T/etc/ssl" "$T/var/tmp" "$T/var/lib/y" "$T/opt"
chmod 700 "$T/usr/lib/x" "$T/etc/ssl" "$T/var/lib/y"; chmod 1777 "$T/var/tmp"
cmd=${linea//find \/usr \/etc \/var \/opt/find $T/usr $T/etc $T/var $T/opt}
bash -c "$cmd"
modo() { stat -c %a "$T/$1"; }
caso "usr/lib/x de 700 a 755"  '[ "$(modo usr/lib/x)" = 755 ]'
caso "etc/ssl de 700 a 755"    '[ "$(modo etc/ssl)" = 755 ]'
caso "var/lib/y de 700 a 755"  '[ "$(modo var/lib/y)" = 755 ]'
caso "var/tmp sigue 1777"      '[ "$(modo var/tmp)" = 1777 ]'
echo "fallas: $fallas"
exit $fallas
