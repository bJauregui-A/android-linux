#!/usr/bin/bash
# B11: una sesión X11 en fondo (vista cerrada o con otra instancia al frente) no debe gastar en dibujar. Mide la CPU
# (utime + stime, en ticks de 10 ms) que gastan en N segundos el servidor :x11 de la instancia y los procesos que se
# le pidan. Solo lectura, por adb; la sesión tiene que estar en fondo y con algo que se redibuje (un reloj con
# segundos, un `watch -n0.1 date` en la terminal).
#   pruebas/x11/fondo.sh <instancia> <máximo de ticks> <proceso>...     p. ej.  sfce-3756 20 xfwm4 xfce4-terminal
cd "$(dirname "$0")/../.." || exit 1
P=dev.ben4shot.glibcprueba.sdk36
inst=$1 max=$2; shift 2
SEG=${SEG:-20}
fallas=0

ticks() { adb shell "run-as $P cat /proc/$1/stat" 2>/dev/null | sed 's/.*) //' | awk '{print $12 + $13}'; }

# el servidor de la instancia: su /tmp/.X11-unix/X10 apunta a files/x11/ (ranura :x11) o a files/x11/<letra>/
destino=$(adb shell "run-as $P readlink files/instancias/$inst/tmp/.X11-unix/X10")
case "$destino" in
  */files/x11/.X11-unix/X10) proc=$P:x11 ;;
  */files/x11/?/.X11-unix/X10) proc=$P:x11$(basename "$(dirname "$(dirname "$destino")")") ;;
  *) echo "FALLA $inst no tiene servidor X (X10 -> '$destino')"; exit 1 ;;
esac
declare -A pid
pid[:x11]=$(adb shell ps -A -o PID,NAME | awk -v n="$proc" '$2 == n {print $1}')
for n in "$@"; do
  pid[$n]=$(adb shell ps -A -o PID,ARGS | grep "instancias/$inst/usr/bin/$n\b" | grep -v grep | awk 'NR == 1 {print $1}')
done

declare -A antes
for n in "${!pid[@]}"; do
  [ -n "${pid[$n]}" ] || { echo "FALLA no encontré $n en $inst"; fallas=$((fallas + 1)); continue; }
  antes[$n]=$(ticks "${pid[$n]}")
done
sleep "$SEG"
for n in "${!antes[@]}"; do
  d=$(( $(ticks "${pid[$n]}") - antes[$n] ))
  if [ "$d" -le "$max" ]; then echo "OK    $n gastó $d ticks en ${SEG} s (máximo $max)"
  else echo "FALLA $n gastó $d ticks en ${SEG} s (máximo $max)"; fallas=$((fallas + 1)); fi
done

echo "fallas: $fallas"
[ $fallas -eq 0 ]
