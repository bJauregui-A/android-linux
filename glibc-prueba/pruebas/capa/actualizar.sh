#!/usr/bin/bash
# B23: con MODO=actualizar, instalar.sh extrae la capa nueva del APK sobre una instancia ya instalada, instala su glibc,
# deja el hash nuevo y ejecuta el comando siguiente (la terminal o el escritorio). No toca el home. Si falla, no abre
# nada. Corre en el PC con un APK de mentira (un archivo con la capa en un offset):  pruebas/capa/actualizar.sh
cd "$(dirname "$0")/../.." || exit 1
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
A=var/lib/linux-android

# capa chica y APK de mentira
mkdir -p "$T/capa/etc/skel" "$T/capa/usr/local/share/linux-android/glibc" "$T/capa/usr/local/bin"
echo "zshrc nuevo" > "$T/capa/etc/skel/.zshrc"
echo "nueva libc.so.6" > "$T/capa/usr/local/share/linux-android/glibc/libc.so.6"
echo "de la capa" > "$T/capa/usr/local/bin/algo"
tar -czf "$T/capa.tgz" -C "$T/capa" .
head -c 1000 /dev/urandom > "$T/apk"; cat "$T/capa.tgz" >> "$T/apk"
HASH=$(sha256sum "$T/capa.tgz" | cut -d' ' -f1)
{ head -c 1000 /dev/urandom; printf '\037\213'; head -c 4000 /dev/urandom; } > "$T/apk-roto"

# instancia <dir>: instalada con la capa anterior, usuario "user" con su .zshrc cambiado
instancia() {
    mkdir -p "$1/$A" "$1/usr/lib" "$1/usr/local/turnip" "$1/etc/skel" "$1/home/user"
    echo viejo > "$1/$A/capa.sha256"
    echo "vieja libc.so.6" > "$1/usr/lib/libc.so.6"
    echo "zshrc viejo" > "$1/etc/skel/.zshrc"
    echo "mío" > "$1/home/user/.zshrc"
    echo marca > "$1/home/user/marca"
}
# actualizar <instancia> <apk> <largo>: como la app, con el comando siguiente que deja una marca
actualizar() {
    GLIBC_PREFIX=$1 APK=$2 CAPA_OFF=1000 CAPA_LEN=$3 CAPA_SHA256=$HASH MODO=actualizar \
        sh -c "$(cat apk/instalar.sh)" instalar.sh sh -c 'echo corrió > "$0/siguiente"' "$1" > "$1.salida" 2>&1
}

I=$T/i1; instancia "$I"
actualizar "$I" "$T/apk" "$(stat -c %s "$T/capa.tgz")"; rc=$?
caso "sale bien"  '[ $rc -eq 0 ]'
caso "extrae la capa"  'grep -qx "de la capa" "$I/usr/local/bin/algo"'
caso "instala la glibc nueva"  'grep -qx "nueva libc.so.6" "$I/usr/lib/libc.so.6"'
caso "respalda la glibc anterior"  'grep -qx "vieja libc.so.6" "$I/$A/glibc-anterior/libc.so.6"'
caso "deja el hash nuevo"  '[ "$(cat "$I/$A/capa.sha256")" = "$HASH" ]'
caso "no deja la marca actualizando"  '[ ! -e "$I/$A/actualizando" ]'
caso "ejecuta el comando siguiente"  '[ -e "$I/siguiente" ]'
caso "no toca un archivo del home"  'grep -qx marca "$I/home/user/marca"'
caso "no toca el .zshrc cambiado del usuario"  'grep -qx "mío" "$I/home/user/.zshrc"'
caso "/etc/skel sí se actualiza"  'grep -qx "zshrc nuevo" "$I/etc/skel/.zshrc"'

# /system/bin/sh (bionic) no arranca con el LD_PRELOAD de glibc de la instancia: la app lo pasa aparte y vuelve
# antes del exec
I=$T/i4; instancia "$I"
LINUX_LD_PRELOAD=/usr/local/turnip/lib/libegl-zink.so GLIBC_PREFIX=$I APK=$T/apk CAPA_OFF=1000 \
    CAPA_LEN=$(stat -c %s "$T/capa.tgz") CAPA_SHA256=$HASH MODO=actualizar sh -c "$(cat apk/instalar.sh)" instalar.sh \
    sh -c 'echo "$LD_PRELOAD|${LINUX_LD_PRELOAD-sin}" > "$0/siguiente"' "$I" > /dev/null 2>&1
caso "el comando siguiente recibe el LD_PRELOAD de la instancia"  \
  '[ "$(cat "$I/siguiente" 2>/dev/null)" = "/usr/local/turnip/lib/libegl-zink.so|sin" ]'

# instalar.sh cambia PATH (/system/bin primero), TMPDIR (ruta de Android) y umask para sí mismo: el comando siguiente
# (la sesión de la instancia) los recibe como los dejó la app, y sin las variables del actualizador
I=$T/i6; instancia "$I"
(umask 077; PATH=/usr/bin:/bin TMPDIR=/tmp/de-la-app GLIBC_PREFIX=$I APK=$T/apk CAPA_OFF=1000 \
    CAPA_LEN=$(stat -c %s "$T/capa.tgz") CAPA_SHA256=$HASH MODO=actualizar /usr/bin/sh -c "$(cat apk/instalar.sh)" \
    instalar.sh /usr/bin/sh -c 'printf "%s|%s|%s|%s\n" "$PATH" "$TMPDIR" "$(umask)" "${MODO-}${APK-}${CAPA_OFF-}${CAPA_LEN-}${CAPA_SHA256-}" > "$0/siguiente"' "$I" > /dev/null 2>&1)
caso "el comando siguiente recibe PATH, TMPDIR y umask de la app, sin las variables del actualizador"  \
  '[ "$(cat "$I/siguiente" 2>/dev/null)" = "/usr/bin:/bin|/tmp/de-la-app|0077|" ]'

I=$T/i2; instancia "$I"
actualizar "$I" "$T/apk-roto" 4002; rc=$?
caso "extracción fallida: sale con error"  '[ $rc -ne 0 ]'
caso "extracción fallida: no escribe el hash nuevo"  'grep -qx viejo "$I/$A/capa.sha256"'
caso "extracción fallida: no deja la marca (usr/lib no se tocó)"  '[ ! -e "$I/$A/actualizando" ]'
caso "extracción fallida: no ejecuta el comando siguiente"  '[ ! -e "$I/siguiente" ]'
caso "extracción fallida: no toca la glibc"  'grep -qx "vieja libc.so.6" "$I/usr/lib/libc.so.6"'

I=$T/i3; instancia "$I"; echo "$HASH" > "$I/$A/capa.sha256"
actualizar "$I" "$T/apk" "$(stat -c %s "$T/capa.tgz")"; rc=$?
caso "al día: no extrae nada"  '[ ! -e "$I/usr/local/bin/algo" ]'
caso "al día: ejecuta el comando siguiente"  '[ $rc -eq 0 ] && [ -e "$I/siguiente" ]'

# migraciones: actualizar las corre después de la glibc; si una falla, no deja el hash nuevo ni abre nada
mkdir -p "$T/capa-m"; cp -a "$T/capa/." "$T/capa-m/"; mkdir -p "$T/capa-m/usr/local/share/linux-android/migraciones"
echo 'echo hecho > "$GLIBC_PREFIX/migro"' > "$T/capa-m/usr/local/share/linux-android/migraciones/001-algo.sh"
echo 'exit 1' > "$T/capa-m/usr/local/share/linux-android/migraciones/002-falla.sh"
tar -czf "$T/capa-m.tgz" -C "$T/capa-m" .
head -c 1000 /dev/urandom > "$T/apk-m"; cat "$T/capa-m.tgz" >> "$T/apk-m"
printf '#!/usr/bin/bash\nexec bash "$GLIBC_PREFIX$2"\n' > "$T/cargador"; chmod +x "$T/cargador"
I=$T/i5; instancia "$I"
GLIBC_LOADER=$T/cargador GLIBC_PREFIX=$I APK=$T/apk-m CAPA_OFF=1000 CAPA_LEN=$(stat -c %s "$T/capa-m.tgz") \
    CAPA_SHA256=$HASH MODO=actualizar sh -c "$(cat apk/instalar.sh)" instalar.sh \
    sh -c 'echo corrió > "$0/siguiente"' "$I" > /dev/null 2>&1; rc=$?
caso "corre las migraciones pendientes"  '[ -e "$I/migro" ] && [ "$(cat "$I/$A/migracion")" = 001 ]'
caso "migración fallida: sale con error, sin hash nuevo y sin abrir"  \
  '[ $rc -ne 0 ] && grep -qx viejo "$I/$A/capa.sha256" && [ ! -e "$I/siguiente" ]'

[ $fallas -eq 0 ] || { echo "--- salida de i1:"; cat "$T/i1.salida"; }
echo "fallas: $fallas"
[ $fallas -eq 0 ]
