#!/usr/bin/bash
# B94: abrir un escritorio Wayland en otra instancia no cierra el sway de esta.
# Corre dentro de la instancia, después de abrir sway en ella y luego en otra:
#   scripts/probar-en-telefono.sh <instancia> pruebas/escritorios/sway-vivo.sh 60
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }
R=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
sock=$(ls "$R"/sway-ipc.*.sock 2>/dev/null | head -1)

caso "hay un socket IPC de sway"  '[ -S "$sock" ]'
caso "sway responde por IPC"  '[ -S "$sock" ] && timeout 3 swaymsg -s "$sock" -t get_version >/dev/null'

echo "fallas: $fallas"
[ "$fallas" -eq 0 ]
