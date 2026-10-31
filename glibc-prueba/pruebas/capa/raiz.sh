#!/usr/bin/bash
# B47: la raíz de la instancia nace en el modo de su distro: Debian 755, Arch 555. Android crea la carpeta en 700
# (umask 077) y el tar de Android (toybox) no aplica la entrada ./ de un tar, así que lo fija instalar.sh.
# Corre en el PC:  pruebas/capa/raiz.sh
cd "$(dirname "$0")/../.." || exit 1
eval "$(sed -n '/^fijar_raiz() {/,/^}/p' apk/instalar.sh)"
type fijar_raiz >/dev/null 2>&1 || { echo "FALLA no se encontró fijar_raiz en apk/instalar.sh"; exit 1; }
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }
T=$(mktemp -d); trap 'chmod 755 "$T"/*; rm -rf "$T"' EXIT

for par in apt:755 pacman:555; do
    b=${par%:*}; m=${par#*:}
    mkdir -p "$T/$b"; chmod 700 "$T/$b"
    P="$T/$b" GLIBC_PKG_BACKEND=$b fijar_raiz
    caso "backend $b deja la raíz en $m"  '[ "$(stat -c %a "$T/$b")" = '$m' ]'
done

echo "fallas: $fallas"
[ $fallas -eq 0 ]
