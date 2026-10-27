#!/usr/bin/bash
# B23: al actualizar, la capa se extrae con las mismas exclusiones con que se instaló. Una instancia sin entorno
# (sin usr/local/turnip) no recibe la parte gráfica; una con escritorio la recibe entera.
# Corre en el PC:  pruebas/capa/exclusiones.sh
cd "$(dirname "$0")/../.." || exit 1
eval "$(sed -n '/^exclusiones_graficas() {/,/^}/p; /^exclusiones_capa() {/,/^}/p' apk/instalar.sh)"
type exclusiones_capa >/dev/null 2>&1 || { echo "FALLA no se encontró exclusiones_capa en apk/instalar.sh"; exit 1; }
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

mkdir -p "$T/sin/usr/local" "$T/con/usr/local/turnip"
x=$(exclusiones_capa "$T/sin")
for p in 'usr/local/turnip*' 'usr/local/mesa-gl*' 'usr/local/wlroots*' 'usr/local/sway*' \
         'usr/local/lib/libudmabuf-shim.so' 'opt/gtk2*' 'etc/skel/.config/kitty*'; do
    caso "sin usr/local/turnip excluye $p"  'printf "%s\n" "$x" | grep -qxF -- "--exclude=$p"'
done
caso "con usr/local/turnip no excluye nada"  '[ -z "$(exclusiones_capa "$T/con")" ]'

echo "fallas: $fallas"
[ $fallas -eq 0 ]
