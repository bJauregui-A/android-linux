#!/usr/bin/bash
# B96: /tmp y /var/tmp son 1777 (sticky, de todos) como en Linux, y Debian trae /mnt y /media; las instancias anteriores los
# tenían 755 y sin esas carpetas. Se puede correr dos veces: no toca lo que ya existe. MIGRAR_RAIZ solo lo usa la prueba del PC.
R=${MIGRAR_RAIZ:-}
for d in tmp var/tmp; do
    if [ -d "$R/$d" ] && [ ! -L "$R/$d" ] && [ "$(stat -c %a "$R/$d")" != 1777 ]; then
        chmod 1777 "$R/$d"
    fi
done
if [ -e "$R/usr/bin/apt-get" ]; then
    for d in mnt media; do
        [ -e "$R/$d" ] || mkdir -m 755 "$R/$d"
    done
fi
exit 0
