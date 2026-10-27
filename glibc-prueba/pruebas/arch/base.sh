#!/usr/bin/bash
# La base de Arch (scripts/bootstrap.py) lleva nuestra glibc encima de la de Arch: un pacman -Syu no debe pisarla.
# Corre en el PC, genera la base real:  pruebas/arch/base.sh
cd "$(dirname "$0")/../.." || exit 1
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }
d=$(mktemp -d); trap 'rm -rf "$d"' EXIT
python3 scripts/bootstrap.py --prefix /data/user/0/prueba/files/arch --glibc glibc/salida/usr/lib --out "$d/base.tar" pacman >"$d/salida" 2>&1 \
  || { echo "FALLA no se pudo generar la base"; tail -5 "$d/salida"; exit 1; }
tar -xOf "$d/base.tar" etc/pacman.conf > "$d/pacman.conf"
caso "pacman.conf tiene IgnorePkg con glibc"  'grep -Eq "^IgnorePkg[[:space:]]*=.*(^|[ =])glibc([ ]|$)" "$d/pacman.conf"'
echo "fallas: $fallas"
[ $fallas -eq 0 ]
