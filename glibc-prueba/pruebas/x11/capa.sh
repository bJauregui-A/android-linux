#!/usr/bin/bash
# B36: el servidor X11 de la instancia entrega su pantalla a SurfaceFlinger como una capa "x11" (ASurfaceControl) con
# un buffer del tamaño de la pantalla X, que el HWC compone como overlay (sin pasar por la GPU). Solo lectura, por adb;
# el escritorio X11 tiene que estar a la vista.  TAM=WxH si la pantalla X no mide lo que la pantalla del teléfono.
#   pruebas/x11/capa.sh <instancia>
cd "$(dirname "$0")/../.." || exit 1
P=dev.ben4shot.glibcprueba.sdk36
inst=$1
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }

destino=$(adb shell "run-as $P readlink files/instancias/$inst/tmp/.X11-unix/X10")
case "$destino" in
  */files/x11/.X11-unix/X10) proc=$P:x11 ;;
  */files/x11/?/.X11-unix/X10) proc=$P:x11$(basename "$(dirname "$(dirname "$destino")")") ;;
  *) echo "FALLA $inst no tiene servidor X (X10 -> '$destino')"; exit 1 ;;
esac
pid=$(adb shell ps -A -o PID,NAME | awk -v n="$proc" '$2 == n {print $1}')
[ -n "$pid" ] || { echo "FALLA no hay proceso $proc"; exit 1; }

sf=$(adb shell dumpsys SurfaceFlinger)
# la capa x11 del proceso del servidor:  "x11#<id> flags:.. pid=<pid>"
id=$(grep -oE "x11#[0-9]+ flags:[0-9]+ a:[0-9]+ pid=$pid " <<<"$sf" | head -1 | grep -oE "#[0-9]+" | tr -d '#')
caso "SurfaceFlinger tiene la capa x11 del proceso $proc (pid $pid)"  '[ -n "$id" ]'
[ -n "$id" ] || { echo "fallas: $fallas"; exit 1; }
capa=$(sed -n "/^  Layer \[$id\] x11#$id/,/^  Layer \[/p" <<<"$sf")

if [ -z "$TAM" ]; then
  read -r a b < <(adb shell wm size | grep -oE '[0-9]+x[0-9]+' | tail -1 | tr x ' ')
  TAM="${a}x${b}|${b}x${a}"   # la pantalla X sigue la orientación de la vista
fi
buf=$(grep -oE "geomBufferSize=\[0 0 [0-9]+ [0-9]+\]" <<<"$capa" | head -1 | grep -oE "[0-9]+ [0-9]+\]" | tr -d ']' | tr ' ' x)
caso "la capa tiene un buffer de $buf, del tamaño de la pantalla X ($TAM)"  'grep -qE "^($TAM)$" <<<"$buf"'
caso "el buffer lo compone el HWC como overlay (composition type=DEVICE)"  'grep -q "composition type=DEVICE" <<<"$capa"'

echo "fallas: $fallas"
[ $fallas -eq 0 ]
