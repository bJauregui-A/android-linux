#!/usr/bin/bash
# B11: la configuración de meson que usa x11/compilar.sh deja apagados GLX, DRI, MIT-SHM, XDMCP, TCP y el
# socket abstracto, y el servidor toma las carpetas del socket y del lock que le pasa la app (parches de
# xtrans y de os/utils.c; sin ellas, las de siempre).
# Corre en el PC:  pruebas/x11/configuracion.sh
cd "$(dirname "$0")/../.." || exit 1
export LC_ALL=C
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }

x11/compilar.sh xserver >/tmp/x11-compilar-xserver.log 2>&1 || { echo "FALLA x11/compilar.sh xserver terminó con error"; exit 1; }
B=$(echo x11/build/xorg-server-*/ | cut -d' ' -f1)
CFG=${B}include/dix-config.h
opcion() { meson introspect --buildoptions "$B" | python3 -c "
import json,sys
print(next(o['value'] for o in json.load(sys.stdin) if o['name']=='$1'))"; }

for o in glx dri1 dri2 dri3 mitshm xdmcp listen_tcp listen_local; do
  caso "opción $o apagada"  "[ \"\$(opcion $o)\" = False ] || [ \"\$(opcion $o)\" = false ]"
done
caso "opción listen_unix encendida"  "[ \"\$(opcion listen_unix)\" = True ] || [ \"\$(opcion listen_unix)\" = true ]"
caso "dix-config.h sin LISTEN_TCP, LISTEN_LOCAL, HAS_SHM, GLXEXT ni XDMCP"  \
  "! grep -E '^#define (LISTEN_TCP|LISTEN_LOCAL|HAS_SHM|MITSHM|GLXEXT|XDMCP)' $CFG"
caso "dix-config.h con LISTEN_UNIX"  "grep -qE '^#define LISTEN_UNIX' $CFG"
caso "el servidor lee X11_UNIX_DIR (socket)"  "grep -q X11_UNIX_DIR x11/salida/libxserver.so"
caso "el servidor lee X11_LOCK_DIR (lock)"    "grep -q X11_LOCK_DIR x11/salida/libxserver.so"

echo "fallas: $fallas"
[ $fallas -eq 0 ]
