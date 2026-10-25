# Primer arranque, parte Android (asset del APK): TerminalService lo corre con /system/bin/sh
# en la terminal cuando falta la instalación. Extrae base.tgz y capa.tgz leyéndolos directo
# del APK (assets sin comprimir: APK, *_OFF y *_LEN los pasa Instalador.java) y sigue con
# primer-arranque.sh dentro de Arch. Se puede repetir: si ya extrajo, va directo a pacman.
set -e
umask 022
ARCH_PATH="/usr/local/bin:/usr/bin"
PATH=/system/bin:$PATH
P=$GLIBC_PREFIX
E=$P/var/lib/linux-android
mkdir -p "$E"
[ -e "$P/var/lib/arch-android" ] || ln -sfn linux-android "$P/var/lib/arch-android" 2>/dev/null || mkdir -p "$P/var/lib/arch-android"
LOG=$P/tmp/instalacion-extraccion.log
mkdir -p "$P/tmp" "$P/dev/shm/.sysv" 2>/dev/null || true
export TMPDIR="$P/tmp"   # los heredocs de sh (mksh) necesitan un tmp escribible; /data/local no lo es
chmod 1777 "$P/dev/shm" "$P/dev/shm/.sysv" 2>/dev/null || true

# Recuadros: ancho real de la terminal (stty/tput; 60 si no hay).
_medir() {
    _a=$(stty size 2>/dev/null </dev/tty | cut -d' ' -f2) || _a=
    case $_a in ''|*[!0-9]*) _a=$(tput cols 2>/dev/null </dev/tty) || _a= ;; esac
    case $_a in ''|*[!0-9]*) _a=${COLUMNS:-} ;; esac
    case $_a in ''|*[!0-9]*) _a=60 ;; esac
    [ "$_a" -ge 20 ] || _a=20
    _AN=$_a
}
# se mide una vez aquí (dentro de un pipe o de $(...) stty ya no ve la terminal) y de nuevo con SIGWINCH
_medir
trap _medir WINCH
_ancho() { echo "$_AN"; }
# columnas visibles de un texto: sin secuencias de color y sin bytes de continuación UTF-8
_vis() { printf '%s' "$1" | sed "s/$(printf '\033')\[[0-9;]*m//g" | LC_ALL=C tr -d "$(printf '\200-\277')" | wc -c; }
_rep() { [ "$1" -gt 0 ] && printf '%*s' "$1" '' | sed 's/ /─/g'; }
# caja_sup COLOR [TITULO_FMT args...] · caja_med COLOR · caja_inf COLOR · caja_lin COLOR FMT args...
caja_sup() {
    _c=$1; _w=$(_ancho)
    if [ -n "$2" ]; then
        _f=$2; shift 2
        _t=$(printf "$_f" "$@")
        _n=$((_w - 5 - $(_vis "$_t"))); [ "$_n" -ge 1 ] || _n=1
        printf '%b┌─ %s %s┐\e[0m\n' "$_c" "$_t" "$(_rep $_n)"
    else
        printf '%b┌%s┐\e[0m\n' "$_c" "$(_rep $((_w - 2)))"
    fi
}
caja_med() { printf '%b├%s┤\e[0m\n' "$1" "$(_rep $(($(_ancho) - 2)))"; }
caja_inf() { printf '%b└%s┘\e[0m\n' "$1" "$(_rep $(($(_ancho) - 2)))"; }
# una fila del recuadro con el texto ya formateado (sin plegar)
_fila() {
    _n=$(($(_ancho) - 2 - $(_vis "$2"))); [ "$_n" -ge 0 ] || _n=0
    printf '%b│\e[0m%s%*s%b│\e[0m\n' "$1" "$2" "$_n" '' "$1"
}
# si el texto no cabe se pliega (sin colores) en varias filas dentro del recuadro
caja_lin() {
    _c=$1; _f=$2; shift 2
    _b=$(printf "$_f" "$@")
    _w=$(_ancho)
    if [ "$(_vis "$_b")" -le $((_w - 2)) ]; then
        _fila "$_c" "$_b"
    else
        printf '%s' "$_b" | sed "s/$(printf '\033')\[[0-9;]*m//g; s/^ *//" | fmt -w $((_w - 6)) |
            while IFS= read -r _l; do _fila "$_c" "  $_l"; done
    fi
}

# Limpiar pantalla y mostrar banner
ESCRITORIO_PREVIO=$(cat "$E/escritorio" "$P/var/lib/arch-android/escritorio" 2>/dev/null | head -n 1 || true)
printf '\033[2J\033[H'
caja_sup '\e[1;38;5;141m'
if [ "$GLIBC_PKG_BACKEND" = "apt" ]; then
    caja_lin '\e[1;38;5;141m' '  \e[1;38;5;51mINSTALADOR DE DEBIAN ARM64\e[0m'
else
    caja_lin '\e[1;38;5;141m' '  \e[1;38;5;51mINSTALADOR DE ARCH LINUX ARM\e[0m'
fi
if [ "$ESCRITORIO_PREVIO" = "sin-entorno" ]; then
    caja_lin '\e[1;38;5;141m' '  \e[38;5;250mExtracción del sistema base ligero (modo consola/servidor)\e[0m'
else
    caja_lin '\e[1;38;5;141m' '  \e[38;5;250mExtracción del sistema base y capa acelerada por GPU\e[0m'
fi
caja_inf '\e[1;38;5;141m'

# Comprobar espacio antes de escribir cientos de MB
LIBRES=$(df -Pk "$P" | awk 'END {print $4}')
case "$LIBRES" in ''|*[!0-9]*) LIBRES=0;; esac
LIBRES_MIB=$((LIBRES / 1024))

echo; caja_sup '\e[1;38;5;111m' '[1/2] Verificación de Almacenamiento'
caja_lin '\e[1;38;5;111m' '  Espacio libre disponible: \e[1;38;5;48m%d MiB\e[0m (Recomendado: 3072 MiB)' "$LIBRES_MIB"
caja_inf '\e[1;38;5;111m'

if [ "$LIBRES" -lt 3145728 ]; then
    printf '\e[1;38;5;214mHay menos de 3 GiB libres. ¿Continuar de todos modos? [s/N]: \e[0m'
    read -r seguir
    case "$seguir" in s|S|si|SI|Si|sí|SÍ) ;; *) echo "Instalación cancelada; libera espacio y vuelve a abrir la app."; exit 1;; esac
fi

extraer() { # extraer <offset> <largo> <qué> [tar options...]
    OFF="$1"
    LEN="$2"
    QUE="$3"
    shift 3
    printf '\e[1;38;5;81m==> Extrayendo:\e[0m %s...\n' "$QUE"
    : > "$LOG"
    zflag=""
    case $(tail -c +$(($OFF + 1)) "$APK" | head -c 2 | od -An -tx1 2>/dev/null | tr -d ' \n') in
        1f8b) zflag="-z" ;;
    esac
    if tail -c +$(($OFF + 1)) "$APK" | head -c "$LEN" | tar $zflag -xf - -C "$P" "$@" 2> "$LOG"; then
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
    echo; caja_sup '\e[1;38;5;111m' '[2/2] Extracción de Capas y Binarios Nativos'
    if [ "$GLIBC_PKG_BACKEND" = "apt" ]; then
        extraer "$BASE_OFF" "$BASE_LEN" "Debian ARM64 base (dpkg/apt + glibc propia)"
    else
        extraer "$BASE_OFF" "$BASE_LEN" "Arch Linux ARM base (pacman + glibc propia)"
    fi
    if [ "$ESCRITORIO_PREVIO" = "sin-entorno" ]; then
        extraer "$CAPA_OFF" "$CAPA_LEN" "Scripts y utilidades base (sin capa GPU)" \
            --exclude='usr/local/turnip*' \
            --exclude='usr/local/mesa-gl*' \
            --exclude='usr/local/wlroots*' \
            --exclude='usr/local/sway*' \
            --exclude='usr/local/lib/libudmabuf-shim.so' \
            --exclude='opt/gtk2*' \
            --exclude='etc/skel/.config/kitty*' \
            --exclude='usr/local/share/*/juegos*'
    else
        extraer "$CAPA_OFF" "$CAPA_LEN" "Capa GPU (Turnip, Zink, Mesa, wlroots, configs)"
    fi
    touch "$E/extraido"
    # Asegurar enlaces simbólicos de retrocompatibilidad
    [ -e "$P/var/lib/arch-android" ] || ln -sfn linux-android "$P/var/lib/arch-android" 2>/dev/null || true
    if [ -d "$P/usr/local/share/linux-android" ] && [ ! -e "$P/usr/local/share/arch-android" ]; then
        ln -sfn linux-android "$P/usr/local/share/arch-android" 2>/dev/null || true
    elif [ -d "$P/usr/local/share/arch-android" ] && [ ! -e "$P/usr/local/share/linux-android" ]; then
        ln -sfn arch-android "$P/usr/local/share/linux-android" 2>/dev/null || true
    fi
    # Normalizar permisos de directorios base a 755 para evitar warnings de pacman
    find "$P/usr" "$P/etc" "$P/var" "$P/opt" -type d -exec chmod 755 {} + 2>/dev/null || true
    mkdir -p "$P/etc/services.d" "$P/usr/lib/systemd/system" 2>/dev/null || true
    caja_inf '\e[1;38;5;111m'
fi

# Enlaces de compatibilidad para bash y binarios base entre /bin y /usr/bin
[ -e "$P/bin/bash" ] && [ ! -e "$P/usr/bin/bash" ] && ln -sfn /bin/bash "$P/usr/bin/bash" 2>/dev/null || true
[ -e "$P/usr/bin/bash" ] && [ ! -e "$P/bin/bash" ] && ln -sfn /usr/bin/bash "$P/bin/bash" 2>/dev/null || true
[ -e "$P/bin/sh" ] && [ ! -e "$P/usr/bin/sh" ] && ln -sfn /bin/sh "$P/usr/bin/sh" 2>/dev/null || true

# Asegurar llavero de firmas GPG de Debian para apt
if [ -f "$P/usr/share/keyrings/debian-archive-keyring.gpg" ]; then
    mkdir -p "$P/etc/apt/trusted.gpg.d"
    rm -f "$P/etc/apt/trusted.gpg.d/debian-archive-keyring.gpg"
    cp "$P/usr/share/keyrings/debian-archive-keyring.gpg" "$P/etc/apt/trusted.gpg.d/debian-archive-keyring.gpg" 2>/dev/null || true
fi

# Wrapper provisional de sudo (root virtual): solo hasta que el primer arranque deje el sudo real
# (marca /etc/sudoers.d/10-linux-android).
mkdir -p "$P/usr/local/bin"
[ -e "$P/etc/sudoers.d/10-linux-android" ] || cat <<'EOF' > "$P/usr/local/bin/sudo"
#!/bin/bash
export GLIBC_FAKEROOT=1
while [ $# -gt 0 ]; do
    case "$1" in
        -E|--preserve-env|-s|-i)
            shift ;;
        -u)
            shift 2 ;;
        --)
            shift; break ;;
        *=*)
            export "$1"; shift ;;
        *)
            break ;;
    esac
done
exec "$@"
EOF
[ -e "$P/etc/sudoers.d/10-linux-android" ] || chmod 755 "$P/usr/local/bin/sudo" 2>/dev/null || true

# Configuración de APT para Android sin root si es backend apt
if [ "$GLIBC_PKG_BACKEND" = "apt" ]; then
    mkdir -p "$P/etc/apt/apt.conf.d"
    cat <<'EOF' > "$P/etc/apt/apt.conf.d/99android"
APT::Sandbox::User "root";
DPkg::Options {
   "--force-not-root";
   "--force-bad-path";
};
Acquire::Languages "none";
Acquire::Check-Valid-Until "false";
EOF

    # Repositorios oficiales de Debian con validacion directa de llave GPG
    cat <<'EOF' > "$P/etc/apt/sources.list"
deb [signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb [signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] http://deb.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
deb [signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
EOF

    # Grupos y usuarios esenciales para servicios como ssh
    if [ -f "$P/etc/group" ]; then
        grep -q "^_ssh:" "$P/etc/group" || echo "_ssh:x:101:" >> "$P/etc/group"
        grep -q "^ssh:" "$P/etc/group" || echo "ssh:x:102:" >> "$P/etc/group"
    fi
    if [ -f "$P/etc/passwd" ]; then
        grep -q "^sshd:" "$P/etc/passwd" || echo "sshd:x:100:65534::/run/sshd:/usr/sbin/nologin" >> "$P/etc/passwd"
        mkdir -p "$P/run/sshd" 2>/dev/null || true
    fi
    # Debian no usa ld.so.cache: sin esto las sesiones de sshd (entorno limpio, sin PAM) no encuentran
    # libtinfo y demás en /lib/aarch64-linux-gnu y bash muere al entrar por ssh.
    mkdir -p "$P/etc/ssh/sshd_config.d" 2>/dev/null || true
    echo "SetEnv LD_LIBRARY_PATH=/usr/lib/aarch64-linux-gnu:/lib/aarch64-linux-gnu:/usr/lib:/lib" \
        > "$P/etc/ssh/sshd_config.d/20-debian-libs.conf"

    # Enlaces de compatibilidad awk y nologin
    [ -x "$P/usr/bin/mawk" ] && [ ! -e "$P/usr/bin/awk" ] && ln -sfn mawk "$P/usr/bin/awk" 2>/dev/null || true
    [ -e "$P/usr/bin/awk" ] && [ ! -e "$P/bin/awk" ] && ln -sfn /usr/bin/awk "$P/bin/awk" 2>/dev/null || true
    [ ! -e "$P/usr/sbin/nologin" ] && ln -sfn /bin/false "$P/usr/sbin/nologin" 2>/dev/null || true

    # Stubs para herramientas init de paquetes deb
    if [ ! -x "$P/usr/sbin/update-rc.d" ]; then
        printf '#!/bin/sh\nexit 0\n' > "$P/usr/sbin/update-rc.d" 2>/dev/null || true
        chmod +x "$P/usr/sbin/update-rc.d" 2>/dev/null || true
    fi

    # Stub de mountpoint para paquetes que lo comprueban
    if [ ! -x "$P/usr/bin/mountpoint" ]; then
        printf '#!/bin/sh\nexit 1\n' > "$P/usr/bin/mountpoint" 2>/dev/null || true
        chmod +x "$P/usr/bin/mountpoint" 2>/dev/null || true
        ln -sfn /usr/bin/mountpoint "$P/bin/mountpoint" 2>/dev/null || true
    fi

    # Marcar usr-is-merged en dpkg status para evitar convert-usrmerge
    if [ -f "$P/var/lib/dpkg/status" ] && ! grep -q "^Package: usr-is-merged" "$P/var/lib/dpkg/status"; then
        printf "Package: usr-is-merged\nStatus: install ok installed\nPriority: optional\nSection: oldlibs\nInstalled-Size: 13\nMaintainer: Marco d'Itri <md@linux.it>\nArchitecture: all\nVersion: 37~deb12u1\nDescription: Transitional package to assert a merged-/usr system\n\n" >> "$P/var/lib/dpkg/status"
    fi
fi

# DNS de Android (el tar trae uno de respaldo)
rm -f "$P/etc/resolv.conf"
for s in $ANDROID_DNS; do echo "nameserver $s"; done > "$P/etc/resolv.conf"
cd "$P"
echo ""
echo "➜ Iniciando configuración del entorno Linux..."
echo ""
export GLIBC_PREFIX="$P"
export GLIBC_LOADER="$GLIBC_LOADER"
export LD_LIBRARY_PATH="/usr/lib/aarch64-linux-gnu:/lib/aarch64-linux-gnu:/usr/lib:/lib:${LD_LIBRARY_PATH:-}"
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

BASH_BIN="/bin/bash"
[ -x "$P/usr/bin/bash" ] && BASH_BIN="/usr/bin/bash"
[ -x "$P/bin/bash" ] && BASH_BIN="/bin/bash"

PA_SCRIPT="/usr/local/share/linux-android/primer-arranque.sh"
[ -f "$P/$PA_SCRIPT" ] || PA_SCRIPT="/usr/local/share/arch-android/primer-arranque.sh"
exec "$GLIBC_LOADER" "$BASH_BIN" "$PA_SCRIPT"
