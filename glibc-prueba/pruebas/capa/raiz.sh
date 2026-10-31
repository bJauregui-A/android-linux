#!/usr/bin/bash
# B47: la raíz de la instancia nace en el modo de su distro: Debian 755, Arch 555. Android crea la carpeta en 700
# (umask 077) y el tar de Android (toybox) no aplica la entrada ./ de un tar, así que lo fija instalar.sh.
# Corre en el PC:  pruebas/capa/raiz.sh
cd "$(dirname "$0")/../.." || exit 1
eval "$(sed -n '/^fijar_raiz() {/,/^}/p; /^fijar_temporales() {/,/^}/p' apk/instalar.sh)"
for f in fijar_raiz fijar_temporales; do
    type $f >/dev/null 2>&1 || { echo "FALLA no se encontró $f en apk/instalar.sh"; exit 1; }
done
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }
T=$(mktemp -d); trap 'chmod 755 "$T"/*; rm -rf "$T"' EXIT

for par in apt:755 pacman:555; do
    b=${par%:*}; m=${par#*:}
    mkdir -p "$T/$b"; chmod 700 "$T/$b"
    P="$T/$b" GLIBC_PKG_BACKEND=$b fijar_raiz
    caso "backend $b deja la raíz en $m"  '[ "$(stat -c %a "$T/$b")" = '$m' ]'
done

# B96: /tmp y /var/tmp nacen 1777 (el tar de Android no conserva el sticky): de todos, como en Linux
mkdir -p "$T/t/tmp" "$T/t/var/tmp"; chmod 755 "$T/t/tmp" "$T/t/var/tmp"
P="$T/t" fijar_temporales
caso "/tmp queda 1777"  '[ "$(stat -c %a "$T/t/tmp")" = 1777 ]'
caso "/var/tmp queda 1777"  '[ "$(stat -c %a "$T/t/var/tmp")" = 1777 ]'
mkdir -p "$T/s"
P="$T/s" fijar_temporales
caso "sin /tmp ni /var/tmp no falla ni los crea"  '[ $? -eq 0 ] && [ ! -e "$T/s/tmp" ]'

echo "fallas: $fallas"
[ $fallas -eq 0 ]
