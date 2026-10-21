# Primer arranque, parte Android (asset del APK): TerminalService lo corre con /system/bin/sh
# en la terminal cuando falta el Arch. Extrae base.tgz y capa.tgz leyéndolos directo
# del APK (assets sin comprimir: APK, *_OFF y *_LEN los pasa Instalador.java) y sigue con
# primer-arranque.sh dentro de Arch. Se puede repetir: si ya extrajo, va directo a pacman.
set -e
ARCH_PATH=$PATH
PATH=/system/bin
P=$GLIBC_PREFIX
E=$P/var/lib/arch-android
LOG=$P/tmp/instalacion-extraccion.log
mkdir -p "$P/tmp"
echo "Instalador de Arch Linux para Android"
echo "Los archivos del sistema se guardarán en el almacenamiento privado de la app."
echo "No cierres la app durante la instalación. Puedes volver a intentarlo si algo falla."

# Comprobar espacio antes de escribir cientos de MB y descargar paquetes. Menos de 3 GiB puede
# alcanzar para el escritorio mínimo, pero no para todos los grupos opcionales.
LIBRES=$(df -Pk "$P" | awk 'END {print $4}')
case "$LIBRES" in ''|*[!0-9]*) LIBRES=0;; esac
echo "Espacio libre: $((LIBRES / 1024)) MiB. Recomendado: 3072 MiB o más."
if [ "$LIBRES" -lt 3145728 ]; then
    printf "Hay menos de 3 GiB libres. ¿Continuar de todos modos? [s/N] "
    read -r seguir
    case "$seguir" in s|S|si|SI|Si|sí|SÍ) ;; *) echo "Instalación cancelada; libera espacio y vuelve a abrir la app."; exit 1;; esac
fi

extraer() { # extraer <offset> <largo> <qué>
    echo "==> Extrayendo $3"
    : > "$LOG"
    # tar es la última orden del pipeline: su estado de salida detecta un gzip/tar incompleto.
    if tail -c +$(($1 + 1)) "$APK" | head -c "$2" | tar -xzf - -C "$P" 2> "$LOG"; then
        echo "   listo"
    else
        echo "   falló la extracción. Últimos detalles:"
        tail -n 20 "$LOG"
        return 1
    fi
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
