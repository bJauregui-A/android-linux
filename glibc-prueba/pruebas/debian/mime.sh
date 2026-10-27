#!/usr/bin/bash
# B11: tras instalar Debian, la base MIME está generada. Sin /usr/share/mime/mime.cache gdk-pixbuf ve todo como
# application/octet-stream ("Unrecognized image file format"): Xfce queda sin fondo, íconos ni panel.
# Corre DENTRO de la instancia:  scripts/probar-en-telefono.sh <instancia-debian> pruebas/debian/mime.sh
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }
caso "which existe (lo usan los postinst)"        'command -v which >/dev/null'
caso "existe /usr/share/mime/mime.cache"          '[ -s /usr/share/mime/mime.cache ]'
caso "existe /usr/share/mime/image/png.xml"       '[ -s /usr/share/mime/image/png.xml ]'
echo "fallas: $fallas"
[ $fallas -eq 0 ]
