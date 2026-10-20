#!/bin/sh
# /usr/local/bin/steam: cliente oficial de Steam ARM64 (steam/instalar-steam.sh).
# gtk2 vive aparte en /opt/gtk2 (steam/compilar-gtk2.sh); el resto de las bibliotecas
# que no trae Steam vienen de Arch.
S=$HOME/.local/share/Steam
export LD_LIBRARY_PATH=/opt/gtk2/lib:$S/steamrtarm64:$S/steamrtarm64/libs${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
export DISPLAY=${DISPLAY:-:0}
# Zink por GLX necesita DRI3 y Xwayland no lo tiene (sin glamor): con el override
# glXChooseVisual no encuentra visuales y vgui2 sale. Sin él, GLX usa llvmpipe.
unset MESA_LOADER_DRIVER_OVERRIDE
# El sandbox de CEF necesita namespaces (sin root no hay): "No usable sandbox".
# Xwayland en píxeles reales (xwayland_scale 2.5 en sway): la UI se agranda sola,
# un poco menos que 2.5 para que quepa en la pantalla angosta.
# OpenGL por GPU (proceso GPU de CEF y vgui) con ~/mesa-gl si está (mesa-gl/con-gpu).
C=; [ -x /usr/local/bin/con-gpu ] && C=/usr/local/bin/con-gpu
exec $C "$S/steamrtarm64/steam" -noverifyfiles -no-cef-sandbox -forcedesktopscaling 2 "$@"
