#!/bin/sh
# /usr/local/bin/steam: cliente oficial de Steam ARM64 (steam/instalar-steam.sh).
# gtk2 vive aparte en /opt/gtk2 (steam/compilar-gtk2.sh); el resto de las bibliotecas
# que no trae Steam vienen de Arch.
S=$HOME/.local/share/Steam
export LD_LIBRARY_PATH=/opt/gtk2/lib:$S/steamrtarm64:$S/steamrtarm64/libs${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
export DISPLAY=${DISPLAY:-:0}
exec "$S/steamrtarm64/steam" -noverifyfiles "$@"
