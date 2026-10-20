# Primer arranque, parte Android (asset del APK): TerminalService lo corre con /system/bin/sh
# en la terminal cuando falta el Arch. Extrae base.tgz y capa.tgz leyéndolos directo
# del APK (assets sin comprimir: APK, *_OFF y *_LEN los pasa Instalador.java) y sigue con
# primer-arranque.sh dentro de Arch. Se puede repetir: si ya extrajo, va directo a pacman.
set -e
ARCH_PATH=$PATH
PATH=/system/bin
P=$GLIBC_PREFIX
E=$P/var/lib/arch-android
extraer() { # extraer <offset> <largo> <qué>
    echo "==> Extrayendo $3"
    tail -c +$(($1 + 1)) "$APK" | head -c "$2" | tar -xzvf - -C "$P" |
        awk 'NR % 400 == 0 { printf "."; fflush() } END { printf " %d archivos\n", NR }'
}
mkdir -p "$E"
touch "$E/instalando"
if [ ! -e "$E/extraido" ]; then
    extraer "$BASE_OFF" "$BASE_LEN" "Arch Linux ARM mínimo (pacman y glibc propia)"
    extraer "$CAPA_OFF" "$CAPA_LEN" "lo propio (sway, wlroots, Turnip, mesa-gl, configs)"
    touch "$E/extraido"
fi
# DNS de Android (el tar trae uno de respaldo)
rm -f "$P/etc/resolv.conf"
for s in $ANDROID_DNS; do echo "nameserver $s"; done > "$P/etc/resolv.conf"
cd "$P"
PATH=$ARCH_PATH
exec "$GLIBC_LOADER" /usr/bin/bash /usr/local/share/arch-android/primer-arranque.sh
