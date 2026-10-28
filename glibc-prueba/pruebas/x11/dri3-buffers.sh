#!/usr/bin/bash
# B36: compila y corre dri3-buffers.c DENTRO de la app (probar-en-telefono.sh), en una instancia con gcc y los
# encabezados de xcb; las instancias comparten el servidor X de la app (DISPLAY :10). Con un escritorio X11 abierto,
# desde el PC:
#   pruebas/x11/dri3-buffers.sh <instancia-con-gcc>                       prueba 13: copia
#   pruebas/x11/dri3-buffers.sh <instancia-con-gcc> --pantalla-completa   prueba 14: flip
cd "$(dirname "$0")/../.." || exit 1
inst=$1 args=$2
[ -n "$inst" ] || { echo "uso: $0 <instancia-con-gcc> [--pantalla-completa]" >&2; exit 2; }
s=$(mktemp --suffix=.sh); trap 'rm -f "$s"' EXIT
cat > "$s" <<EOF
export DISPLAY=\${DISPLAY:-:10}
# una instancia sin sesión abierta no tiene el socket en su /tmp: se enlaza el del servidor de la app mientras dura
enlace=
if [ ! -e /tmp/.X11-unix/X10 ]; then
  mkdir -p /tmp/.X11-unix; ln -s /data/user/0/dev.ben4shot.glibcprueba.sdk36/files/x11/.X11-unix/X10 /tmp/.X11-unix/X10 && enlace=1
fi
d=\$(mktemp -d)
base64 -d > "\$d/dri3-buffers.c" <<'FUENTE'
$(base64 -w76 pruebas/x11/dri3-buffers.c)
FUENTE
gcc -O2 -o "\$d/dri3-buffers" "\$d/dri3-buffers.c" -lxcb -lxcb-dri3 -lxcb-present || { echo "FALLA no compila"; exit 1; }
"\$d/dri3-buffers" $args; rc=\$?
rm -rf "\$d"; [ -n "\$enlace" ] && rm -f /tmp/.X11-unix/X10
exit \$rc
EOF
scripts/probar-en-telefono.sh "$inst" "$s" 120; rc=$?
# al cerrarse la ventana, Present hace unflip: la capa x11-flip queda oculta y vuelve a verse la pantalla del servidor
if [ "$args" = --pantalla-completa ]; then
  sleep 1
  if adb shell dumpsys SurfaceFlinger 2>/dev/null | grep -A25 "^  Layer \[[0-9]*\] x11-flip" | grep -q "invisible reason=hidden"; then
    echo "OK    al cerrar la ventana la capa x11-flip queda oculta (unflip)"
  else
    echo "FALLA al cerrar la ventana la capa x11-flip sigue a la vista"; rc=1
  fi
fi
exit $rc
