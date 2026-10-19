#!/bin/bash
# CPU de la app y de sway con vkcube 5 s dentro de sway, con la app al frente o atrás.
# Sin cerrar nada (no reinstala ni hace force-stop): vkcube se lanza con `swaymsg exec`
# porque desde run-as Turnip no ve la GPU. "atras" pulsa HOME y vuelve a abrir el escritorio.
#   scripts/medir-fondo.sh frente
#   scripts/medir-fondo.sh atras
P=dev.ben4shot.glibcprueba.sdk36
N=$(adb shell dumpsys package $P | grep -m1 legacyNativeLibraryDir | cut -d= -f2- | tr -d '\r')/arm64
APP=$(adb shell pidof $P | tr -d '\r')
SW=$(adb shell "ps -A -o PID,ARGS -u u0_a294" | awk '/--argv0 sway /{print $1}')
U=$(adb shell "run-as $P id -u" | tr -d '\r')
cpu(){ adb shell "run-as $P sh -c 'for p in $APP $SW; do set -- \$(sed \"s/.*) //\" /proc/\$p/stat); echo \$((\${12}+\${13})); done'"; }
[ "$1" = atras ] && { adb shell input keyevent KEYCODE_HOME; sleep 2; }
adb shell "run-as $P env WL_LIB='$N' sh /data/local/tmp/wl.sh /usr/bin/swaymsg -s /run/user/$U/sway-ipc.$U.$SW.sock exec \"timeout 8 vkcube --wsi wayland\"" >/dev/null
sleep 1.5; a=($(cpu)); sleep 5; b=($(cpu))
echo "$1, vkcube 5 s: app $(( (b[0]-a[0])*10 )) ms, sway $(( (b[1]-a[1])*10 )) ms"
sleep 2
[ "$1" = atras ] && adb shell am start -n $P/dev.ben4shot.glibcprueba.WaylandActivity >/dev/null 2>&1
true
