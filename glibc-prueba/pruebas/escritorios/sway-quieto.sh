#!/usr/bin/bash
# B94: el sway de una instancia que no está al frente no dibuja (casi no gasta CPU), aunque
# un cliente suyo pinte sin parar (un kitty con `yes`, que el script abre y cierra).
# Corre dentro de la instancia A, con sway abierto en A y otra instancia al frente:
#   scripts/probar-en-telefono.sh <instancia> pruebas/escritorios/sway-quieto.sh 60
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }
R=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
sock=$(ls "$R"/sway-ipc.*.sock 2>/dev/null | head -1)
pid=${sock#*sway-ipc.*.}; pid=${pid%.sock}

# utime+stime (ticks) de /proc/<pid>/stat; el nombre puede llevar espacios, se corta tras el último ')'.
ticks() { sed 's/.*) //' "/proc/$1/stat" | awk '{print $12 + $13}'; }

caso "hay un socket IPC de sway"  '[ -S "$sock" ]'
if [ -d "/proc/$pid" ]; then
    swaymsg -s "$sock" exec "kitty --class quieto-carga sh -c yes" >/dev/null; sleep 3
    antes=$(ticks "$pid"); sleep 5; despues=$(ticks "$pid")
    swaymsg -s "$sock" '[app_id=quieto-carga] kill' >/dev/null; sleep 1; pkill -x yes
    gastado=$((despues - antes))
    echo "      sway $pid gastó $gastado ticks en 5 s"
    caso "sway de fondo gasta menos de 5 ticks en 5 s"  '[ "$gastado" -lt 5 ]'
else
    caso "se encontró el pid de sway"  'false'
fi

echo "fallas: $fallas"
[ "$fallas" -eq 0 ]
