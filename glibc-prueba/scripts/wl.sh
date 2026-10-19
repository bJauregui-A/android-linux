# Corre un programa Linux conectado a sway sin cerrar la app (desde el PC, por run-as):
#   adb push scripts/wl.sh /data/local/tmp/wl.sh
#   N=$(adb shell dumpsys package dev.ben4shot.glibcprueba.sdk36 | grep -m1 legacyNativeLibraryDir | cut -d= -f2- | tr -d '\r')/arm64
#   adb shell "run-as dev.ben4shot.glibcprueba.sdk36 env WL_LIB='$N' sh /data/local/tmp/wl.sh /usr/bin/wl-paste -l"
# $N cambia con cada `adb install`. LD_PRELOAD no va afuera (rompe el sh de Android): usar /usr/bin/env.
N=$WL_LIB
F=/data/data/dev.ben4shot.glibcprueba.sdk36/files/archlinux
export GLIBC_PREFIX=$F GLIBC_LOADER=$N/libldp.so HOME=/home/user PATH=/usr/bin LANG=C.UTF-8 XDG_RUNTIME_DIR=/run/user/$(id -u) WAYLAND_DISPLAY=wayland-1 GLYCIN_DISABLE_SANDBOX=i-know-the-risks
exec /system/bin/timeout ${WL_T:-5} $N/libldp.so "$@"
