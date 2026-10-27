#!/usr/bin/bash
# B23 (Paso 4): si Android mata la app a mitad de apt (pasó por falta de memoria al crear una Debian con xfce-x11),
# dpkg queda interrumpido y apt-get falla en cada reintento con "dpkg was interrupted, you must manually run
# 'dpkg --configure -a'". backend_instalar lo repara antes de cada intento.
# Corre en el PC:  pruebas/debian/dpkg-interrumpido.sh
cd "$(dirname "$0")/../.." || exit 1
for f in backend_limpiar_lock requisitos_frenados liberar_pines chfn_tolerante chfn_restaurar dpkg_reparar backend_instalar; do
  eval "$(sed -n "/^$f() {/,/^}/p" apk/primer-arranque.sh)"
  type $f >/dev/null 2>&1 || { echo "FALLA no se encontró $f en apk/primer-arranque.sh"; exit 1; }
done
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }
d=$(mktemp -d); trap 'rm -rf "$d"' EXIT
mkdir -p "$d/bin"
# dpkg y apt-get de mentira: apt-get falla mientras dpkg siga interrumpido (marca $d/interrumpido)
printf '#!/bin/sh\n[ "$1 $2" = "--configure -a" ] && rm -f %s/interrumpido\necho "dpkg $*" >> %s/llamadas\n' "$d" "$d" > "$d/bin/dpkg"
printf '#!/bin/sh\necho "apt-get $*" >> %s/llamadas\n[ -e %s/interrumpido ] && { echo "E: dpkg was interrupted, you must manually run '"'"'dpkg --configure -a'"'"' to correct the problem."; exit 100; }\nexit 0\n' "$d" "$d" > "$d/bin/apt-get"
chmod +x "$d/bin/"*
sudo() { "$@"; }
sleep() { :; }
export PATH=$d/bin:$PATH SUDO_CMD= CHFN=$d/no-existe TMPDIR=$d BACKEND=apt

touch "$d/interrumpido"
backend_instalar xfce4 > "$d/salida" 2>&1; rc=$?
caso "con dpkg interrumpido, la instalación termina bien"  '[ $rc -eq 0 ]'
caso "repara dpkg antes de apt-get"  '[ "$(head -1 "$d/llamadas")" = "dpkg --configure -a" ]'
caso "apt-get no falla ni una vez"  '! grep -q "dpkg was interrupted" "$d/salida"'

# Cortado a mitad de desempaquetar: el paquete queda half-installed y dpkg --configure -a no lo arregla ("package is
# in a very bad inconsistent state; you should reinstall it"). Hay que reinstalarlo.
printf '#!/bin/sh\necho "ii  xterm"\n[ -e %s/a-medias ] && echo "iHR libpaper-utils"\nexit 0\n' "$d" > "$d/bin/dpkg-query"
printf '#!/bin/sh\necho "apt-get $*" >> %s/llamadas\ncase "$*" in *--reinstall*libpaper-utils*) rm -f %s/a-medias; exit 0;; esac\n[ -e %s/a-medias ] && { echo "E: Sub-process /usr/bin/dpkg returned an error code (1)"; exit 100; }\nexit 0\n' "$d" "$d" "$d" > "$d/bin/apt-get"
chmod +x "$d/bin/"*
rm -f "$d/llamadas"; touch "$d/a-medias"
backend_instalar xfce4 > "$d/salida" 2>&1; rc=$?
caso "con un paquete a medio instalar, la instalación termina bien"  '[ $rc -eq 0 ]'
caso "reinstala el paquete a medias antes del apt-get de siempre"  \
  '[ "$(sed -n 2p "$d/llamadas")" = "apt-get install -y --reinstall libpaper-utils" ]'
caso "no reinstala los que están bien"  '! grep -q "reinstall.*xterm" "$d/llamadas"'

echo "fallas: $fallas"
[ $fallas -eq 0 ]
