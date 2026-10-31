#!/usr/bin/bash
# B94: el socket Wayland de la app vive en files/wayland/ y cada instancia lo enlaza desde su XDG_RUNTIME_DIR,
# así borrar una instancia no deja sin Wayland a las demás.
# Corre dentro de la instancia:  scripts/probar-en-telefono.sh <instancia> pruebas/escritorios/wayland-socket.sh 60
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }
R=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}

caso "wayland-0 es un enlace a files/wayland/wayland-0"  '[ -L "$R/wayland-0" ] && [[ $(readlink "$R/wayland-0") == */files/wayland/wayland-0 ]]'
caso "wayland-0.lock es un enlace a files/wayland/wayland-0.lock"  '[ -L "$R/wayland-0.lock" ] && [[ $(readlink "$R/wayland-0.lock") == */files/wayland/wayland-0.lock ]]'
caso "wayland-0 lleva a un socket"  '[ -S "$R/wayland-0" ]'

echo "fallas: $fallas"
[ "$fallas" -eq 0 ]
