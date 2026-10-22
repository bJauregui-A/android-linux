# Primer arranque, parte Android (asset del APK): TerminalService lo corre con /system/bin/sh
# en la terminal cuando falta la instalación. Extrae base.tgz y capa.tgz leyéndolos directo
# del APK (assets sin comprimir: APK, *_OFF y *_LEN los pasa Instalador.java) y sigue con
# primer-arranque.sh dentro de Arch. Se puede repetir: si ya extrajo, va directo a pacman.
set -e
ARCH_PATH=$PATH
PATH=/system/bin:$PATH
P=$GLIBC_PREFIX
E=$P/var/lib/arch-android
LOG=$P/tmp/instalacion-extraccion.log
mkdir -p "$P/tmp" "$P/dev/shm/.sysv" 2>/dev/null || true
chmod 1777 "$P/dev/shm" "$P/dev/shm/.sysv" 2>/dev/null || true

# Limpiar pantalla y mostrar banner
printf '\033[2J\033[H'
printf '\e[1;38;5;141m┌────────────────────────────────────────────────────────────┐\e[0m\n'
printf '\e[1;38;5;141m│\e[0m  \e[1;38;5;51mINSTALADOR DE ARCH LINUX ARM\e[0m                             \e[1;38;5;141m│\e[0m\n'
printf '\e[1;38;5;141m│\e[0m  \e[38;5;250mExtracción del sistema base y capa acelerada por GPU\e[0m     \e[1;38;5;141m│\e[0m\n'
printf '\e[1;38;5;141m└────────────────────────────────────────────────────────────┘\e[0m\n'

# Comprobar espacio antes de escribir cientos de MB
LIBRES=$(df -Pk "$P" | awk 'END {print $4}')
case "$LIBRES" in ''|*[!0-9]*) LIBRES=0;; esac
LIBRES_MIB=$((LIBRES / 1024))

printf '\n\e[1;38;5;111m┌─ [1/2] Verificación de Almacenamiento ─────────────────────┐\e[0m\n'
printf '\e[1;38;5;111m│\e[0m  Espacio libre disponible: \e[1;38;5;48m%d MiB\e[0m (Recomendado: 3072 MiB)\n' "$LIBRES_MIB"
printf '\e[1;38;5;111m└────────────────────────────────────────────────────────────┘\e[0m\n'

if [ "$LIBRES" -lt 3145728 ]; then
    printf '\e[1;38;5;214mHay menos de 3 GiB libres. ¿Continuar de todos modos? [s/N]: \e[0m'
    read -r seguir
    case "$seguir" in s|S|si|SI|Si|sí|SÍ) ;; *) echo "Instalación cancelada; libera espacio y vuelve a abrir la app."; exit 1;; esac
fi

extraer() { # extraer <offset> <largo> <qué>
    printf '\e[1;38;5;81m==> Extrayendo:\e[0m %s...\n' "$3"
    : > "$LOG"
    if tail -c +$(($1 + 1)) "$APK" | head -c "$2" | tar -xzf - -C "$P" 2> "$LOG"; then
        printf '    \e[1;38;5;48m✔ Listo\e[0m\n'
    else
        printf '    \e[1;38;5;196m✖ Falló la extracción. Detalles:\e[0m\n'
        tail -n 20 "$LOG"
        return 1
    fi
}

mkdir -p "$E"
touch "$E/instalando"
if [ ! -e "$E/extraido" ]; then
    printf '\n\e[1;38;5;111m┌─ [2/2] Extracción de Capas y Binarios Nativos ─────────────┐\e[0m\n'
    extraer "$BASE_OFF" "$BASE_LEN" "Arch Linux ARM base (pacman + glibc propia)"
    extraer "$CAPA_OFF" "$CAPA_LEN" "Capa GPU (Turnip, Zink, Mesa, wlroots, configs)"
    touch "$E/extraido"
    printf '\e[1;38;5;111m└────────────────────────────────────────────────────────────┘\e[0m\n'
fi

# DNS de Android (el tar trae uno de respaldo)
rm -f "$P/etc/resolv.conf"
for s in $ANDROID_DNS; do echo "nameserver $s"; done > "$P/etc/resolv.conf"
cd "$P"
echo ""
echo "➜ Iniciando configuración del entorno Arch Linux..."
echo ""
PATH="$ARCH_PATH" exec "$GLIBC_LOADER" /usr/bin/bash /usr/local/share/arch-android/primer-arranque.sh
