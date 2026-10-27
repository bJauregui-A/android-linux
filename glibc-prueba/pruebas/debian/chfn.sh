#!/usr/bin/bash
# B67: dentro de la app chfn falla por PAM ("Authentication failure"); adduser lo llama en los postinst (pulseaudio,
# polkitd, rtkit, colord...) y dpkg deja esos paquetes a medias. Mientras corre apt, chfn se desvía a un envoltorio
# que no falla; al terminar vuelve el original.
# Corre en el PC:  pruebas/debian/chfn.sh
cd "$(dirname "$0")/../.." || exit 1
for f in chfn_tolerante chfn_restaurar; do
  eval "$(sed -n "/^$f() {/,/^}/p" apk/primer-arranque.sh)"
  type $f >/dev/null 2>&1 || { echo "FALLA no se encontró $f en apk/primer-arranque.sh"; exit 1; }
done
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }
d=$(mktemp -d); trap 'rm -rf "$d"' EXIT

# dpkg-divert falso: --rename mueve el archivo como el de verdad.
dpkg-divert() {
  local divert= accion= f
  while [ $# -gt 0 ]; do
    case $1 in --divert) divert=$2; shift ;; --add) accion=add ;; --remove) accion=remove ;; -*) ;; *) f=$1 ;; esac
    shift
  done
  case $accion in
    add) mv "$f" "$divert"; echo "$f $divert" > "$d/desvios" ;;
    remove) read -r f divert < "$d/desvios"; mv "$divert" "$f"; rm -f "$d/desvios" ;;
  esac
}
export SUDO_CMD= CHFN=$d/chfn
# El chfn de verdad dentro de la app: falla y deja rastro de sus argumentos.
printf '#!/bin/sh\necho "$@" > %s/args\necho "chfn: PAM: Authentication failure" >&2\nexit 1\n' "$d" > "$d/chfn"
chmod 4755 "$d/chfn"; orig=$(cat "$d/chfn")

chfn_tolerante
caso "con el desvío, chfn sale bien aunque el original falle"   '"$d/chfn" -f "PulseAudio daemon" pulse 2>/dev/null'
caso "el envoltorio pasa los argumentos al original"            '[ "$(cat "$d/args")" = "-f PulseAudio daemon pulse" ]'
chfn_tolerante
caso "desviar dos veces no pisa el original"                    '[ "$(cat "$d/chfn.android")" = "$orig" ]'
chfn_restaurar
caso "al restaurar vuelve el chfn original"                     '[ "$(cat "$d/chfn")" = "$orig" ]'
caso "al restaurar no queda el desvío"                          '[ ! -e "$d/chfn.android" ]'
caso "el original conserva el bit setuid"                       '[ -u "$d/chfn" ]'
caso "restaurar sin desvío no hace nada"                        'chfn_restaurar && [ "$(cat "$d/chfn")" = "$orig" ]'
echo "fallas: $fallas"
[ $fallas -eq 0 ]
