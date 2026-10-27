#!/usr/bin/bash
# B23 (Paso 4): corre DENTRO de una instancia creada con el APK anterior, después de instalar el APK nuevo y abrirla.
# Solo lectura. Los @...@ los reemplaza quien la sube (Paso 4 de B23, desde el PC con sed):
#   @CAPA@ capa.sha256 del APK · @LIBC@ sha256 de glibc/salida/usr/lib/libc.so.6 · @LIBC_ANTES@ el de la instancia
#   antes de actualizar · @MARCA@ archivo del home creado antes · @SIN_ENTORNO@ 1 si es una instancia sin entorno
#   scripts/probar-en-telefono.sh <instancia> <este script con los valores>
E=/var/lib/linux-android
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }
sha() { sha256sum "$1" 2>/dev/null | cut -d' ' -f1; }

caso "25 capa.sha256 de la instancia = el del APK"  '[ "$(cat $E/capa.sha256 2>/dev/null)" = "@CAPA@" ]'
caso "26 usr/lib/libc.so.6 = la de glibc/salida"  '[ "$(sha /usr/lib/libc.so.6)" = "@LIBC@" ]'
if [ -d /usr/lib/aarch64-linux-gnu ]; then
    caso "26 usr/lib/aarch64-linux-gnu/libc.so.6 = la de glibc/salida"  \
      '[ "$(sha /usr/lib/aarch64-linux-gnu/libc.so.6)" = "@LIBC@" ]'
fi
caso "26 glibc-anterior/libc.so.6 = la que tenía antes"  '[ "$(sha $E/glibc-anterior/libc.so.6)" = "@LIBC_ANTES@" ]'
caso "27 la marca del home sigue ahí"  '[ -f "@MARCA@" ]'
caso "27 no quedó la marca actualizando"  '[ ! -e $E/actualizando ]'
if [ "@SIN_ENTORNO@" = 1 ]; then
    caso "28 sin entorno: sigue sin usr/local/turnip"  '[ ! -e /usr/local/turnip ]'
fi

echo "fallas: $fallas"
[ $fallas -eq 0 ]
