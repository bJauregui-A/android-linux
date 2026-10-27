#!/usr/bin/bash
# B67: Xfce (xfce-x11) arranca en Debian 12: sesión X11, sus procesos corriendo y una captura de la pantalla que no
# es de un solo color. Corre DENTRO de la instancia, con el escritorio abierto:
#   scripts/probar-en-telefono.sh --conservar <instancia-debian-12> pruebas/debian/xfce.sh
# La captura queda en /tmp/xfce.xwd de la instancia (se pasa a PNG en el PC). Con xwd: grim es solo de Wayland.
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }
props=$(cat /run/user/*/linux-session.properties 2>/dev/null)
pantalla=$(sed -n 's/^endpoint=//p' <<<"$props")
caso "la sesión es X11"                  'grep -qx protocol=x11 <<<"$props"'
# pgrep ve los procesos de todas las instancias de la app: solo cuentan los que tienen el DISPLAY de esta.
corre() { local pid; for pid in $(pgrep -x "$1"); do grep -qzx "DISPLAY=$pantalla" /proc/$pid/environ 2>/dev/null && return 0; done; return 1; }
for p in xfce4-session xfwm4 xfce4-panel xfdesktop xfsettingsd; do
  caso "corre $p en $pantalla"           '[ -n "$pantalla" ] && corre $p'
done
caso "el servidor X responde en $pantalla" 'DISPLAY=$pantalla xdpyinfo >/dev/null 2>&1'
DISPLAY=$pantalla xwd -root -silent > /tmp/xfce.xwd 2>/dev/null
# Los píxeles están al final del xwd: si son todos iguales, la pantalla está vacía.
colores=$(tail -c 400000 /tmp/xfce.xwd 2>/dev/null | od -An -tx4 -v -w4 | sort -u | wc -l)
caso "la captura tiene contenido ($colores colores distintos, de al menos 20)" '[ "$colores" -ge 20 ]'
echo "fallas: $fallas"
[ $fallas -eq 0 ]
