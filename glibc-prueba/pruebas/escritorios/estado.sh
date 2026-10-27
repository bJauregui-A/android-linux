#!/usr/bin/bash
# B67: estado_escritorio de apk/primer-arranque.sh dice si un escritorio está probado en esta distro y versión
# ($DISTRO está en PROBADO_EN de su escritorio.conf) o es experimental.
# Corre en el PC, sobre carpetas temporales:  pruebas/escritorios/estado.sh
cd "$(dirname "$0")/../.." || exit 1
eval "$(sed -n '/^estado_escritorio() {/,/^}/p' apk/primer-arranque.sh)"
type estado_escritorio >/dev/null 2>&1 || { echo "FALLA no se encontró estado_escritorio"; exit 1; }
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }
d=$(mktemp -d); trap 'rm -rf "$d"' EXIT
ED=$d/escritorios; mkdir -p $ED/xfce-x11
printf 'NOMBRE="Xfce"\nPROBADO_EN="arch"\n' > $ED/xfce-x11/escritorio.conf

DISTRO=arch
caso "probado en arch: probado en arch"            '[ "$(estado_escritorio xfce-x11)" = probado ]'
DISTRO=debian-12
caso "probado solo en arch: experimental en debian-12"  '[ "$(estado_escritorio xfce-x11)" = experimental ]'

# Las recetas reales: Xfce se probó en Debian 12 (prueba 12 de B67), no en Arch.
ED=escritorios
DISTRO=debian-12
caso "xfce-x11 del repo: probado en debian-12"     '[ "$(estado_escritorio xfce-x11)" = probado ]'
DISTRO=arch
caso "xfce-x11 del repo: sigue experimental en arch"  '[ "$(estado_escritorio xfce-x11)" = experimental ]'

echo "fallas: $fallas"
[ $fallas -eq 0 ]
