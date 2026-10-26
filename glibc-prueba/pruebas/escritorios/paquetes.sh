#!/usr/bin/bash
# B67: paquetes_escritorio de apk/primer-arranque.sh da los paquetes de un escritorio para la distro y
# versión de la instancia ($DISTRO), de escritorios/<id>/paquetes-<distro>.txt; nunca los de otra.
# Corre en el PC, sobre carpetas temporales:  pruebas/escritorios/paquetes.sh
cd "$(dirname "$0")/../.." || exit 1
eval "$(sed -n '/^paquetes_escritorio() {/,/^}/p' apk/primer-arranque.sh)"
type paquetes_escritorio >/dev/null 2>&1 || { echo "FALLA no se encontró paquetes_escritorio"; exit 1; }
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }
d=$(mktemp -d); trap 'rm -rf "$d"' EXIT
ED=$d/escritorios; mkdir -p $ED/xfce

printf '# comentario\nxfce4 xfwm4\nxterm\n' > $ED/xfce/paquetes-debian-12.txt
DISTRO=debian-12
caso "da los paquetes declarados para debian-12"  '[ "$(paquetes_escritorio xfce)" = "xfce4 xfwm4 xterm" ]'

mkdir -p $ED/solo-arch; printf 'foot\n' > $ED/solo-arch/paquetes-arch.txt; printf 'foot labwc\n' > $ED/solo-arch/paquetes-debian-13.txt
caso "vacío si solo los declara para arch y debian-13"  '[ -z "$(paquetes_escritorio solo-arch)" ]'

echo "fallas: $fallas"
[ $fallas -eq 0 ]
