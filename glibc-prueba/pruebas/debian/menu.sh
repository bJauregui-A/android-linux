#!/usr/bin/bash
# B67: en una instancia Debian 12 el menú de escritorios es el de tasksel, en su orden, más la consola, y todos
# salen experimentales (ninguno probado todavía en debian-12). Usa las funciones del primer-arranque.sh instalado.
# Solo lectura. Corre DENTRO de la instancia:  scripts/probar-en-telefono.sh <instancia-debian-12> pruebas/debian/menu.sh
PA=/usr/local/share/linux-android/primer-arranque.sh
[ -n "$PRIMER_ARRANQUE" ] && PA=$PRIMER_ARRANQUE
for f in distro_version menu_escritorios estado_escritorio; do
  eval "$(sed -n "/^$f() {/,/^}/p" "$PA")"
  type $f >/dev/null 2>&1 || { echo "FALLA no se encontró $f en $PA"; exit 1; }
done
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }
ED=/usr/local/share/linux-android/escritorios

DISTRO=$(distro_version)
menu=$(menu_escritorios | tr '\n' ' ')
echo "menú ($DISTRO): $menu"
caso "la distro es debian-12" '[ "$DISTRO" = debian-12 ]'
caso "el menú es el de tasksel, en su orden, más la consola" \
  '[ "$menu" = "gnome xfce-x11 gnome-flashback kde cinnamon mate lxde lxqt sin-entorno " ]'
for id in $menu; do
  [ $id = sin-entorno ] && continue
  e=$(estado_escritorio $id)
  caso "$id: experimental ($e)" '[ "$e" = experimental ]'
done
echo "fallas: $fallas"
[ $fallas -eq 0 ]
