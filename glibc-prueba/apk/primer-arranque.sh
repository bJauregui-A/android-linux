#!/usr/bin/bash
# Primer arranque, parte Linux (va en /usr/local/share/arch-android; lo lanza instalar.sh).
# Deja el Arch completo: usuario, llavero, paquetes (lo mínimo + lo que se elija en el menú: ssh,
# audio, Firefox, juegos...) y los ajustes que antes hacían a mano los scripts subir-*.sh.
# Se puede volver a correr (pacman --needed); --elegir vuelve a mostrar el menú.
export PATH="/usr/local/bin:/usr/bin"
D=/usr/local/share/linux-android
[ -d "$D" ] || D=/usr/local/share/arch-android
E=/var/lib/linux-android
[ -d "$E" ] || E=/var/lib/arch-android
mkdir -p "$E" 2>/dev/null || true
[ -e /var/lib/arch-android ] || ln -sfn linux-android /var/lib/arch-android 2>/dev/null || true
[ -e /usr/local/share/arch-android ] || ln -sfn linux-android /usr/local/share/arch-android 2>/dev/null || true

# Funciones de estilo
paso() {
    printf '\n\e[1;38;5;81m┌─ %s\e[0m\n' "$*"
}

# ==============================================================================
# Capa de Abstracción de Gestor de Paquetes (Backend Multi-Distribución)
# ==============================================================================
detectar_backend() {
    if [ -n "${GLIBC_PKG_BACKEND:-}" ]; then
        echo "$GLIBC_PKG_BACKEND"
    elif command -v pacman >/dev/null 2>&1; then
        echo "pacman"
    elif command -v apt-get >/dev/null 2>&1; then
        echo "apt"
    elif command -v apk >/dev/null 2>&1; then
        echo "apk"
    elif command -v dnf >/dev/null 2>&1; then
        echo "dnf"
    else
        echo "desconocido"
    fi
}
BACKEND=$(detectar_backend)

backend_nombre() {
    case "$BACKEND" in
        pacman) echo "Arch Linux ARM (pacman)" ;;
        apt)    echo "Debian / Ubuntu (apt)" ;;
        apk)    echo "Alpine Linux (apk)" ;;
        dnf)    echo "Fedora (dnf)" ;;
        *)      echo "Genérico ($BACKEND)" ;;
    esac
}

backend_soporta_aur() {
    [ "$BACKEND" = "pacman" ]
}

backend_limpiar_lock() {
    case "$BACKEND" in
        pacman)
            [ -f /var/lib/pacman/db.lck ] && ! pgrep -x pacman >/dev/null 2>&1 && rm -f /var/lib/pacman/db.lck
            ;;
        apt)
            [ -f /var/lib/dpkg/lock-frontend ] && ! pgrep -x apt-get >/dev/null 2>&1 && ! pgrep -x dpkg >/dev/null 2>&1 && \
                rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock 2>/dev/null || true
            ;;
    esac
}

backend_iniciar_base() {
    case "$BACKEND" in
        pacman)
            # Asegurar SigLevel = Never para repositorios de SteamOS sin firmas individuales
            if grep -q '\[holo-core\]' /etc/pacman.conf 2>/dev/null; then
                sed -i '/\[holo-core\]/{n;s/^#\?SigLevel\s*=.*/SigLevel = Never/}' /etc/pacman.conf 2>/dev/null || true
                sed -i '/\[holo-extra\]/{n;s/^#\?SigLevel\s*=.*/SigLevel = Never/}' /etc/pacman.conf 2>/dev/null || true
            fi
            paso "Inicializando base y paquetes de sistema (pacman)"
            for d in /var/lib/pacman/local/*/; do
                [ -f "$d/install" ] || continue
                ver=$(sed -n "/^%VERSION%/{n;p}" "$d/desc")
                (cd / && GLIBC_FAKEROOT=1 HOME=/root bash -c ". $d/install; declare -F post_install >/dev/null && post_install $ver" > /dev/null 2>&1)
            done
            paso "Configurando llavero de pacman y certificados SSL"
            backend_limpiar_lock
            sudo pacman-key --init > /dev/null 2>&1 && sudo pacman-key --populate archlinuxarm || true
            sudo update-ca-trust > /dev/null 2>&1 || true
            ;;
        apt)
            paso "Inicializando base y repositorios (apt)"
            backend_limpiar_lock
            # Prevenir que scripts de paquetes intenten iniciar servicios con policy-rc.d
            printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d 2>/dev/null || true
            chmod +x /usr/sbin/policy-rc.d 2>/dev/null || true
            sudo apt-get update > /dev/null 2>&1 || true
            ;;
        *)
            backend_limpiar_lock
            ;;
    esac
}

backend_instalar() {
    local pkgs=("$@")
    [ ${#pkgs[@]} -eq 0 ] && return 0
    case "$BACKEND" in
        pacman)
            for i in 1 2 3; do
                backend_limpiar_lock
                sudo pacman -Syu --needed --noconfirm --overwrite "*" "${pkgs[@]}" && return 0
                [ $i -eq 3 ] && return 1
                printf '\n\e[38;5;214m✖ Falló la descarga en pacman, reintento %d de 2...\e[0m\n' $i
                sleep 3
            done
            ;;
        apt)
            for i in 1 2 3; do
                backend_limpiar_lock
                sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${pkgs[@]}" && return 0
                [ $i -eq 3 ] && return 1
                printf '\n\e[38;5;214m✖ Falló la descarga en apt, reintento %d de 2...\e[0m\n' $i
                sleep 3
            done
            ;;
        *)
            echo "backend no soportado para instalación: $BACKEND" >&2
            return 1
            ;;
    esac
}

resolver_archivo() {
    local base=$1
    if [ -f "$D/${base}-${BACKEND}.txt" ]; then
        echo "$D/${base}-${BACKEND}.txt"
    elif [ -f "$D/${base}.txt" ]; then
        echo "$D/${base}.txt"
    elif [ -f "$(dirname "$0")/${base}-${BACKEND}.txt" ]; then
        echo "$(dirname "$0")/${base}-${BACKEND}.txt"
    elif [ -f "$(dirname "$0")/${base}.txt" ]; then
        echo "$(dirname "$0")/${base}.txt"
    fi
}

falla() {
    printf '\n\e[1;38;5;196m✖ Error: %s\e[0m\n' "$*"
    printf '\n\e[38;5;250mOpciones de recuperación:\e[0m\n'
    printf '  \e[1;38;5;48m[1]\e[0m Reintentar instalación automáticamente\n'
    printf '  \e[1;38;5;81m[2]\e[0m Abrir consola de rescate interactiva\n'
    printf '  \e[1;38;5;196m[3]\e[0m Salir\n'
    read -rp "Selecciona una opción [1]: " opt
    case "$opt" in
        2)
            printf '\n\e[1;38;5;51mEntrando a terminal de rescate. Escribe "exit" para reanudar la instalación.\e[0m\n'
            backend_limpiar_lock
            bash -l
            exec bash "$0"
            ;;
        3)
            exit 1
            ;;
        *)
            backend_limpiar_lock
            exec bash "$0"
            ;;
    esac
}
lista() { for g; do f=$(resolver_archivo "paquetes-$g"); [ -n "$f" ] && sed 's/#.*//' "$f"; done | tr -s ' \n' '  '; }

# Banner de inicio
printf '\033[2J\033[H'
printf '\e[1;38;5;141m┌────────────────────────────────────────────────────────────┐\e[0m\n'
printf '\e[1;38;5;141m│\e[0m  \e[1;38;5;51mCONFIGURACIÓN INICIAL DEL ENTORNO\e[0m                         \e[1;38;5;141m│\e[0m\n'
printf '\e[1;38;5;141m│\e[0m  \e[38;5;250mAsistente interactivo de personalización e instalación\e[0m    \e[1;38;5;141m│\e[0m\n'
printf '\e[1;38;5;141m└────────────────────────────────────────────────────────────┘\e[0m\n'

# Usuario y nombre del dispositivo (una vez; quedan en $E/usuario y /etc/hostname, que la app
# y la glibc leen: TerminalService.usuario(), uname/gethostname desde la 0019)
if [ ! -s $E/usuario ]; then
    printf '\n\e[1;38;5;111m┌─ [1/4] Identidad del Sistema y Usuario ────────────────────┐\e[0m\n'
    while :; do
        printf '\e[1;38;5;111m│\e[0m  \e[1;38;5;48m❯\e[0m Nombre de usuario [user]: '
        read -r N
        N=${N:-user}
        [[ $N =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] && [ "$N" != root ] && break
        printf '\e[1;38;5;111m│\e[0m  \e[38;5;214m✖ Inválido: empieza con minúscula o _, sin espacios ni mayúsculas\e[0m\n'
    done
    echo "$N" > $E/usuario
fi
N=$(cat $E/usuario)
if [ ! -s /etc/hostname ]; then
    S=$(echo "${ANDROID_MODELO:-android}" | tr 'A-Z ' 'a-z-' | tr -cd 'a-z0-9-' | sed 's/^-*//; s/-*$//')
    while :; do
        printf '\e[1;38;5;111m│\e[0m  \e[1;38;5;48m❯\e[0m Nombre del dispositivo [%s]: ' "${S:-android}"
        read -r H
        H=${H:-${S:-android}}
        [[ $H =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]] && break
        printf '\e[1;38;5;111m│\e[0m  \e[38;5;214m✖ Inválido: solo letras, números y guiones\e[0m\n'
    done
    echo "$H" > /etc/hostname
    printf '\e[1;38;5;111m└────────────────────────────────────────────────────────────┘\e[0m\n'
fi
U=$(id -u); G=$(id -g)
grep -q "^$N:" /etc/passwd || echo "$N:x:$U:$G:$N:/home/$N:/usr/bin/zsh" >> /etc/passwd
grep -q "^$N:" /etc/group || echo "$N:x:$G:" >> /etc/group
# Registrar zsh en /etc/shells para que PAM y login no rechacen la shell
grep -q "^/usr/bin/zsh$" /etc/shells 2>/dev/null || echo "/usr/bin/zsh" >> /etc/shells
grep -q "^/bin/zsh$" /etc/shells 2>/dev/null || echo "/bin/zsh" >> /etc/shells
# Normalizar permisos de directorios del sistema para evitar advertencias de pacman
umask 022
find /usr /etc /var /opt -maxdepth 3 -type d -exec chmod 755 {} + 2>/dev/null || true
mkdir -p /etc/services.d /usr/lib/systemd/system 2>/dev/null || true
# El home con las configs de /etc/skel (sway, waybar, kitty, zsh...)
mkdir -p /home/$N/.config
cp -rn /etc/skel/. /home/$N/ 2>/dev/null || true
rmdir /home/user 2>/dev/null

# Contraseña del usuario: la piden el bloqueo de pantalla de los escritorios (KDE, COSMIC, phosh...),
# SSH y las ventanas de autenticación. Se guarda su hash (SHA-512) en /etc/shadow.
contrasena_definida() { grep -q "^$N:[^!*:][^:]*:" /etc/shadow 2>/dev/null; }
pedir_contrasena() {
    local p1 p2 h
    printf '\n\e[1;38;5;111m┌─ [2/4] Seguridad y Autenticación ──────────────────────────┐\e[0m\n'
    printf '\e[1;38;5;111m│\e[0m  Configura la contraseña para \e[1;38;5;48m%s\e[0m:\n' "$N"
    while :; do
        printf '\e[1;38;5;111m│\e[0m  \e[1;38;5;48m❯\e[0m Nueva contraseña: '
        read -rsp "" p1; echo
        [ -n "$p1" ] || { printf '\e[1;38;5;111m│\e[0m  \e[38;5;214m✖ No puede estar vacía\e[0m\n'; continue; }
        printf '\e[1;38;5;111m│\e[0m  \e[1;38;5;48m❯\e[0m Confirmar contraseña: '
        read -rsp "" p2; echo
        [ "$p1" = "$p2" ] && break
        printf '\e[1;38;5;111m│\e[0m  \e[38;5;214m✖ No coinciden, intenta nuevamente\e[0m\n'
    done
    h=$(printf '%s' "$p1" | openssl passwd -6 -stdin) && [ -n "$h" ] || return 1
    touch /etc/shadow && chmod 600 /etc/shadow
    if grep -q "^$N:" /etc/shadow; then
        H=$h D=$(( $(date +%s) / 86400 )) awk -F: -v OFS=: -v n="$N" \
            '$1 == n { $2 = ENVIRON["H"]; $3 = ENVIRON["D"] } { print }' /etc/shadow > /etc/shadow.nuevo \
            && cat /etc/shadow.nuevo > /etc/shadow && rm -f /etc/shadow.nuevo || return 1
    else
        printf '%s:%s:%s:0:99999:7:::\n' "$N" "$h" "$(( $(date +%s) / 86400 ))" >> /etc/shadow
    fi
    chmod 600 /etc/shadow
    printf '\e[1;38;5;111m│\e[0m  \e[1;38;5;48m✔ Contraseña guardada correctamente\e[0m\n'
    printf '\e[1;38;5;111m└────────────────────────────────────────────────────────────┘\e[0m\n'
}
if [ "$1" = --contrasena ]; then
    pedir_contrasena || falla "no se pudo guardar la contraseña"
    exit 0
fi
contrasena_definida || pedir_contrasena || falla "no se pudo guardar la contraseña"
export HOME=/home/$N USER=$N LOGNAME=$N
cd ~

if [ ! -e $E/base-lista ]; then
    backend_iniciar_base
    touch $E/base-lista
fi

# Escritorio: uno, elegido una vez ($E/escritorio; lo arranca /usr/local/bin/sesion-android)
[ "$1" = --elegir ] && rm -f $E/opcionales $E/escritorio
[ "$1" = --escritorio ] && rm -f $E/escritorio
ED=$D/escritorios
if [ ! -s $E/escritorio ]; then
    mapfile -t IDS < <(grep -v '^#' $ED/orden)
    idx_esc=0
    num_esc=${#IDS[@]}

    dibujar_menu_escritorios() {
        printf '\033[2J\033[H'
        printf '\e[1;38;5;111m┌────────────────────────────────────────────────────────────┐\e[0m\n'
        printf '\e[1;38;5;111m│\e[0m  \e[1;38;5;81m[3/4] Selección de Entorno de Escritorio\e[0m                  \e[1;38;5;111m│\e[0m\n'
        printf '\e[1;38;5;111m│\e[0m  \e[38;5;245mUsa ↑/↓ para moverte y Enter para seleccionar entorno\e[0m     \e[1;38;5;111m│\e[0m\n'
        printf '\e[1;38;5;111m├────────────────────────────────────────────────────────────┤\e[0m\n'
        for i in "${!IDS[@]}"; do
            (. $ED/${IDS[$i]}/escritorio.conf
             if [ "$ESTADO" = probado ]; then
                 e=$'\e[1;38;5;48m● PROBADO\e[0m'
             else
                 e=$'\e[38;5;214m○ experimental\e[0m'
             fi
             tam=${TAMANO//[()]/}
             if [ "$i" -eq "$idx_esc" ]; then
                 printf '\e[1;38;5;111m│\e[0m \e[1;38;5;51m❯\e[0m \e[1;38;5;48m[✔]\e[0m \e[1;38;5;15;48;5;238m %-12s\e[0m %-18s \e[1;38;5;252m%-15s\e[0m\e[1;38;5;111m│\e[0m\n' \
                     "$NOMBRE" "$e" "$tam"
             else
                 printf '\e[1;38;5;111m│\e[0m   \e[38;5;245m[ ]\e[0m \e[1;38;5;51m%-13s\e[0m %-18s \e[38;5;248m%-15s\e[0m\e[1;38;5;111m│\e[0m\n' \
                     "$NOMBRE" "$e" "$tam"
             fi
            )
        done
        printf '\e[1;38;5;111m├────────────────────────────────────────────────────────────┤\e[0m\n'
        if [ "$idx_esc" -eq "$num_esc" ]; then
            printf '\e[1;38;5;111m│\e[0m \e[1;38;5;51m❯\e[0m  \e[1;38;5;48m[ ✔ CONFIRMAR Y CONTINUAR ]\e[0m                              \e[1;38;5;111m│\e[0m\n'
        else
            printf '\e[1;38;5;111m│\e[0m    \e[38;5;245m[   Confirmar y continuar   ]\e[0m                              \e[1;38;5;111m│\e[0m\n'
        fi
        printf '\e[1;38;5;111m└────────────────────────────────────────────────────────────┘\e[0m\n'
    }

    while :; do
        dibujar_menu_escritorios
        IFS= read -rsn1 tecla
        if [ "$tecla" = $'\e' ]; then
            read -rsn2 -t 0.1 resto || true
            case "$resto" in
                '[A'|'OA')
                    if [ $idx_esc -gt 0 ]; then
                        ((idx_esc--))
                    fi
                    ;;
                '[B'|'OB')
                    if [ $idx_esc -lt "$num_esc" ]; then
                        ((idx_esc++))
                    fi
                    ;;
            esac
        elif [ "$tecla" = "" ] || [ "$tecla" = $'\n' ] || [ "$tecla" = $'\r' ]; then
            break
        elif [ "$tecla" = " " ]; then
            if [ "$idx_esc" -eq "$num_esc" ]; then
                break
            fi
        fi
    done
    [ "$idx_esc" -eq "$num_esc" ] && idx_esc=$((num_esc - 1))
    echo "${IDS[idx_esc]}" > $E/escritorio
fi
ESC=$(cat $E/escritorio)
if [[ ! "$ESC" =~ ^[a-z0-9-]+$ ]] || [ ! -f "$ED/$ESC/escritorio.conf" ] || [ ! -f "$ED/$ESC/sesion" ]; then
    falla "no existe la receta de escritorio '$ESC' para esta instalación"
fi

SISTEMA_LINUX=arch-arm64
HOME_LINUX=/home/$N
ESCALA=${ANDROID_ESCALA:-2.5}
configurar_escritorio() {
    local perfil=$1 fuente destino archivo
    if [ -d "$ED/$perfil/home" ]; then
        while IFS= read -r -d '' archivo; do
            fuente=${archivo#"$ED/$perfil/home/"}
            destino="$HOME_LINUX/$fuente"
            [ -e "$destino" ] && continue
            mkdir -p "$(dirname "$destino")" || return 1
            sed "s/@ESCALA@/$ESCALA/g" "$archivo" > "$destino" || return 1
            if [ -x "$archivo" ]; then chmod +x "$destino" || return 1; fi
        done < <(find "$ED/$perfil/home" -type f -print0)
    fi
}
paso "Aplicando configuración de $ESC para $SISTEMA_LINUX"
configurar_escritorio "$ESC" || falla "no se pudo aplicar la receta de $ESC"

if [ "$ESC" = "sin-entorno" ]; then
    GRUPOS=(ssh zsh desarrollo adb utilidades)
    TEXTOS=("SSH: Servidor seguro en el puerto 8022"
            "Zsh: Shell interactiva con Starship, eza y utilidades CLI (sin entorno gráfico)"
            "Desarrollo: gcc, meson, git, gdb, strace"
            "ADB local sin PC: depuración inalámbrica"
            "Utilidades: htop, unzip, wget, curl")
    MARCA=(1 1 0 0 1)
else
    GRUPOS=(ssh audio zsh firefox desarrollo adb utilidades)
    TEXTOS=("SSH: Servidor seguro en el puerto 8022"
            "Audio: PipeWire a Altavoz Android vía AudioTrack"
            "Zsh + Kitty: Zsh con Starship y terminal Kitty como en el PC"
            "Firefox con aceleración GPU WebRender"
            "Desarrollo: gcc, meson, git, gdb, strace"
            "ADB local sin PC: depuración inalámbrica"
            "Utilidades: htop, grim, unzip, wget")
    MARCA=(1 1 1 0 0 0 0)
fi

if backend_soporta_aur; then
    GRUPOS+=(aur)
    TEXTOS+=("AUR: yay y paru (ayudantes de paquetes)")
    MARCA+=(1)
fi

paquetes_de_grupo() {
    local g=$1
    local f=$(resolver_archivo "paquetes-$g")
    if [ -n "$f" ]; then
        local raw=$(sed 's/#.*//' "$f" | tr -s ' \n' ' ')
        if [ "$ESC" = "sin-entorno" ]; then
            if [ "$g" = "zsh" ]; then
                raw=$(echo "$raw" | sed -E 's/\b(kitty|foot|ttf-jetbrains-mono-nerd|fonts-jetbrains-mono)\b//g')
            elif [ "$g" = "utilidades" ]; then
                raw=$(echo "$raw" | sed -E 's/\b(grim)\b//g')
            fi
        fi
        echo "$raw" | tr -s ' \n' ' '
    fi
}

declare -A PKG_SEL
for g in "${GRUPOS[@]}"; do
    for p in $(paquetes_de_grupo "$g"); do
        case "$p" in
            yay) PKG_SEL["${g}:${p}"]=0 ;;      # compilación desactivada por defecto si está yay-bin
            paru) PKG_SEL["${g}:${p}"]=0 ;;     # compilación desactivada por defecto si está paru-bin
            paru-bin) PKG_SEL["${g}:${p}"]=0 ;; # yay-bin activado por defecto
            *) PKG_SEL["${g}:${p}"]=1 ;;
        esac
    done
done

editar_paquetes_grupo() {
    local g=$1
    local desc=${TEXTOS[$2]}
    local pkgs=($(paquetes_de_grupo "$g"))
    local n_pkgs=${#pkgs[@]}
    [ "$n_pkgs" -eq 0 ] && return

    local idx_pkg=0
    local scroll_top=0
    local max_visible=10

    while :; do
        printf '\033[2J\033[H'
        printf '\e[1;38;5;111m┌────────────────────────────────────────────────────────────┐\e[0m\n'
        printf '\e[1;38;5;111m│\e[0m  \e[1;38;5;81mPersonalizar módulo: %-37s\e[0m \e[1;38;5;111m│\e[0m\n' "$g"
        printf '\e[1;38;5;111m│\e[0m  \e[38;5;245mUsa ↑/↓, Espacio para marcar/desmarcar, TAB para volver   \e[0m\e[1;38;5;111m│\e[0m\n'
        printf '\e[1;38;5;111m├────────────────────────────────────────────────────────────┤\e[0m\n'

        if [ "$idx_pkg" -lt "$scroll_top" ]; then
            scroll_top=$idx_pkg
        elif [ "$idx_pkg" -ge $((scroll_top + max_visible)) ]; then
            scroll_top=$((idx_pkg - max_visible + 1))
        fi

        local visible_end=$((scroll_top + max_visible))
        [ "$visible_end" -gt "$n_pkgs" ] && visible_end=$n_pkgs

        for ((j = scroll_top; j < visible_end; j++)); do
            local p="${pkgs[$j]}"
            local chk
            if [ "${PKG_SEL["${g}:${p}"]}" = 1 ]; then
                chk=$'\e[1;38;5;48m[✔]\e[0m'
            else
                chk=$'\e[38;5;245m[ ]\e[0m'
            fi

            local p_desc="$p"
            case "$p" in
                yay) p_desc="yay (compilar de aur.archlinux.org/yay.git)" ;;
                yay-bin) p_desc="yay-bin (precompilado de aur.archlinux.org)" ;;
                paru) p_desc="paru (compilar de aur.archlinux.org/paru.git)" ;;
                paru-bin) p_desc="paru-bin (precompilado de aur.archlinux.org)" ;;
                base-devel) p_desc="base-devel (compilación de PKGBUILDs)" ;;
                git) p_desc="git (clonación de repositorios AUR)" ;;
            esac

            if [ "$j" -eq "$idx_pkg" ]; then
                printf '\e[1;38;5;111m│\e[0m \e[1;38;5;51m❯\e[0m %s \e[1;38;5;15;48;5;238m %-52s\e[0m\e[1;38;5;111m│\e[0m\n' "$chk" "${p_desc:0:52}"
            else
                printf '\e[1;38;5;111m│\e[0m   %s \e[38;5;250m%-54s\e[0m\e[1;38;5;111m│\e[0m\n' "$chk" "${p_desc:0:54}"
            fi
        done

        printf '\e[1;38;5;111m├────────────────────────────────────────────────────────────┤\e[0m\n'
        if [ "$idx_pkg" -eq "$n_pkgs" ]; then
            printf '\e[1;38;5;111m│\e[0m \e[1;38;5;51m❯\e[0m  \e[1;38;5;48m[ ✔ GUARDAR Y VOLVER ]\e[0m                                   \e[1;38;5;111m│\e[0m\n'
        else
            printf '\e[1;38;5;111m│\e[0m    \e[38;5;245m[   Guardar y volver (o presiona TAB)   ]\e[0m                \e[1;38;5;111m│\e[0m\n'
        fi
        printf '\e[1;38;5;111m└────────────────────────────────────────────────────────────┘\e[0m\n'

        IFS= read -rsn1 k
        if [ "$k" = $'\e' ]; then
            read -rsn2 -t 0.1 resto || true
            case "$resto" in
                '[A'|'OA')
                    [ $idx_pkg -gt 0 ] && ((idx_pkg--))
                    ;;
                '[B'|'OB')
                    [ $idx_pkg -lt "$n_pkgs" ] && ((idx_pkg++))
                    ;;
            esac
        elif [ "$k" = $'\t' ] || [ "$k" = "q" ] || [ "$k" = "Q" ]; then
            break
        elif [ "$k" = "" ] || [ "$k" = $'\n' ] || [ "$k" = $'\r' ] || [ "$k" = " " ]; then
            if [ "$idx_pkg" -eq "$n_pkgs" ]; then
                break
            else
                local p="${pkgs[$idx_pkg]}"
                local act="${PKG_SEL["${g}:${p}"]:-0}"
                local nuevo=$((1 - act))
                PKG_SEL["${g}:${p}"]=$nuevo
                # Si se activa yay/yay-bin o paru/paru-bin, desmarcar su contraparte conflictiva
                if [ "$nuevo" -eq 1 ]; then
                    case "$p" in
                        yay) PKG_SEL["${g}:yay-bin"]=0 ;;
                        yay-bin) PKG_SEL["${g}:yay"]=0 ;;
                        paru) PKG_SEL["${g}:paru-bin"]=0 ;;
                        paru-bin) PKG_SEL["${g}:paru"]=0 ;;
                    esac
                fi
            fi
        fi
    done

    local sel_cnt=0
    for p in "${pkgs[@]}"; do
        [ "${PKG_SEL["${g}:${p}"]}" = 1 ] && ((sel_cnt++))
    done
    if [ "$sel_cnt" -gt 0 ]; then
        MARCA[$2]=1
    else
        MARCA[$2]=0
    fi
}

if [ -e $E/opcionales ]; then
    for i in "${!GRUPOS[@]}"; do
        if grep -qx "${GRUPOS[$i]}" "$E/opcionales"; then
            MARCA[$i]=1
        else
            MARCA[$i]=0
        fi
    done
else
    idx_actual=0
    num_opciones=${#GRUPOS[@]}

    dibujar_menu_opcionales() {
        printf '\033[2J\033[H'
        printf '\e[1;38;5;111m┌────────────────────────────────────────────────────────────┐\e[0m\n'
        printf '\e[1;38;5;111m│\e[0m  \e[1;38;5;81m[4/4] Módulos y Paquetes Opcionales\e[0m                       \e[1;38;5;111m│\e[0m\n'
        printf '\e[1;38;5;111m│\e[0m  \e[38;5;245mUsa ↑/↓, Espacio marcar/desmarcar, TAB elegir paquetes     \e[0m\e[1;38;5;111m│\e[0m\n'
        printf '\e[1;38;5;111m├────────────────────────────────────────────────────────────┤\e[0m\n'
        for i in "${!GRUPOS[@]}"; do
            local g="${GRUPOS[$i]}"
            local total_p=0 sel_p=0
            for p in $(paquetes_de_grupo "$g"); do
                ((total_p++))
                [ "${PKG_SEL["${g}:${p}"]}" = 1 ] && ((sel_p++))
            done
            local chk
            if [ "${MARCA[$i]}" = 1 ]; then
                chk=$'\e[1;38;5;48m[✔]\e[0m'
            else
                chk=$'\e[38;5;245m[ ]\e[0m'
            fi
            local info_p="($sel_p/$total_p)"
            if [ "$i" -eq "$idx_actual" ]; then
                printf '\e[1;38;5;111m│\e[0m \e[1;38;5;51m❯\e[0m %s \e[1;38;5;15m%-40s\e[0m \e[38;5;81m%-7s\e[0m \e[38;5;245m[TAB]\e[0m\e[1;38;5;111m│\e[0m\n' \
                    "$chk" "${TEXTOS[$i]:0:40}" "$info_p"
            else
                printf '\e[1;38;5;111m│\e[0m   %s \e[38;5;250m%-40s\e[0m \e[38;5;245m%-7s\e[0m      \e[1;38;5;111m│\e[0m\n' \
                    "$chk" "${TEXTOS[$i]:0:40}" "$info_p"
            fi
        done
        printf '\e[1;38;5;111m├────────────────────────────────────────────────────────────┤\e[0m\n'
        if [ "$idx_actual" -eq "$num_opciones" ]; then
            printf '\e[1;38;5;111m│\e[0m \e[1;38;5;51m❯\e[0m  \e[1;38;5;48m[ ✔ ENVIAR Y CONTINUAR ]\e[0m                                 \e[1;38;5;111m│\e[0m\n'
        else
            printf '\e[1;38;5;111m│\e[0m    \e[38;5;245m[   Enviar y continuar   ]\e[0m                                 \e[1;38;5;111m│\e[0m\n'
        fi
        printf '\e[1;38;5;111m└────────────────────────────────────────────────────────────┘\e[0m\n'
    }

    while :; do
        dibujar_menu_opcionales
        IFS= read -rsn1 tecla
        if [ "$tecla" = $'\e' ]; then
            read -rsn2 -t 0.1 resto || true
            case "$resto" in
                '[A'|'OA')
                    if [ $idx_actual -gt 0 ]; then
                        ((idx_actual--))
                    fi
                    ;;
                '[B'|'OB')
                    if [ $idx_actual -lt "$num_opciones" ]; then
                        ((idx_actual++))
                    fi
                    ;;
            esac
        elif [ "$tecla" = $'\t' ]; then
            if [ "$idx_actual" -lt "$num_opciones" ]; then
                MARCA[idx_actual]=1
                editar_paquetes_grupo "${GRUPOS[idx_actual]}" "$idx_actual"
            fi
        elif [ "$tecla" = "" ] || [ "$tecla" = $'\n' ] || [ "$tecla" = $'\r' ]; then
            if [ "$idx_actual" -eq "$num_opciones" ]; then
                break
            else
                nuevo_m=$((1 - MARCA[idx_actual]))
                MARCA[idx_actual]=$nuevo_m
                if [ "$nuevo_m" -eq 1 ]; then
                    g="${GRUPOS[idx_actual]}"
                    for p in $(paquetes_de_grupo "$g"); do
                        case "$p" in
                            yay) PKG_SEL["${g}:${p}"]=0 ;;
                            paru) PKG_SEL["${g}:${p}"]=0 ;;
                            paru-bin) PKG_SEL["${g}:${p}"]=0 ;;
                            *) PKG_SEL["${g}:${p}"]=1 ;;
                        esac
                    done
                fi
            fi
        elif [ "$tecla" = " " ]; then
            if [ "$idx_actual" -eq "$num_opciones" ]; then
                break
            else
                nuevo_m=$((1 - MARCA[idx_actual]))
                MARCA[idx_actual]=$nuevo_m
                if [ "$nuevo_m" -eq 1 ]; then
                    g="${GRUPOS[idx_actual]}"
                    for p in $(paquetes_de_grupo "$g"); do
                        case "$p" in
                            yay) PKG_SEL["${g}:${p}"]=0 ;;
                            paru) PKG_SEL["${g}:${p}"]=0 ;;
                            paru-bin) PKG_SEL["${g}:${p}"]=0 ;;
                            *) PKG_SEL["${g}:${p}"]=1 ;;
                        esac
                    done
                fi
            fi
        elif [ "$tecla" = "s" ] || [ "$tecla" = "S" ]; then
            break
        elif [[ "$tecla" =~ ^[1-8]$ ]]; then
            val=$((tecla - 1))
            nuevo_m=$((1 - MARCA[val]))
            MARCA[val]=$nuevo_m
            if [ "$nuevo_m" -eq 1 ]; then
                g="${GRUPOS[val]}"
                for p in $(paquetes_de_grupo "$g"); do
                    case "$p" in
                        yay) PKG_SEL["${g}:${p}"]=0 ;;
                        paru) PKG_SEL["${g}:${p}"]=0 ;;
                        paru-bin) PKG_SEL["${g}:${p}"]=0 ;;
                        *) PKG_SEL["${g}:${p}"]=1 ;;
                    esac
                done
            fi
        fi
    done

    for i in "${!GRUPOS[@]}"; do [ "${MARCA[$i]}" = 1 ] && echo "${GRUPOS[$i]}"; done > $E/opcionales
fi
elegido() { grep -qx "$1" $E/opcionales; }
grupos="escritorio $(tr '\n' ' ' < $E/opcionales)"

# Recoger paquetes específicos para el gestor del sistema y para AUR (si aplica)
PAQUETES_A_INSTALAR=()
if [ "$ESC" = "sin-entorno" ]; then
    # Modo sin entorno: base de consola sin paquetes gráficos
    f_sin=$(resolver_archivo "paquetes-sin-entorno")
    if [ -n "$f_sin" ]; then
        PAQUETES_A_INSTALAR+=($(sed 's/#.*//' "$f_sin"))
    elif [ "$BACKEND" = "apt" ]; then
        PAQUETES_A_INSTALAR+=("python3" "nano" "jq" "zsh" "openssh-server" "htop" "tmux" "curl" "wget")
    else
        PAQUETES_A_INSTALAR+=("base" "python" "nano" "jq" "zsh" "starship" "openssh" "htop" "tmux" "curl" "wget")
    fi
else
    # Base mínima de escritorio (gráficos, compositor, utilidades esenciales)
    f_esc=$(resolver_archivo "paquetes-escritorio")
    [ -n "$f_esc" ] && PAQUETES_A_INSTALAR+=($(sed 's/#.*//' "$f_esc"))
    # Paquetes específicos del entorno seleccionado
    f_entorno=""
    if [ -f "$ED/$ESC/paquetes-${BACKEND}.txt" ]; then
        f_entorno="$ED/$ESC/paquetes-${BACKEND}.txt"
    elif [ -f "$ED/$ESC/paquetes.txt" ]; then
        f_entorno="$ED/$ESC/paquetes.txt"
    fi
    [ -n "$f_entorno" ] && PAQUETES_A_INSTALAR+=($(sed 's/#.*//' "$f_entorno"))
fi
AUR_A_INSTALAR=()

for i in "${!GRUPOS[@]}"; do
    if [ "${MARCA[$i]}" = 1 ]; then
        g="${GRUPOS[$i]}"
        for p in $(paquetes_de_grupo "$g"); do
            if [ "${PKG_SEL["${g}:${p}"]}" = 1 ]; then
                case "$p" in
                    yay|yay-bin|paru|paru-bin)
                        AUR_A_INSTALAR+=("$p")
                        if [ "$BACKEND" = "pacman" ]; then
                            PAQUETES_A_INSTALAR+=("base-devel" "git")
                        fi
                        ;;
                    *)
                        PAQUETES_A_INSTALAR+=("$p")
                        ;;
                esac
            fi
        done
    fi
done

# Deduplicar lista de paquetes
PAQUETES_A_INSTALAR=($(printf '%s\n' "${PAQUETES_A_INSTALAR[@]}" | sort -u))

printf '\n\e[1;38;5;81m┌─ Descarga e instalación de paquetes (%s) ──────────────────┐\e[0m\n' "$(backend_nombre)"
printf '\e[1;38;5;81m│\e[0m  Módulos: \e[1;38;5;48m%s\e[0m | Escritorio: \e[1;38;5;48m%s\e[0m\n' "$grupos" "$ESC"
printf '\e[1;38;5;81m│\e[0m  Paquetes seleccionados: \e[1;38;5;48m%d\e[0m\n' "${#PAQUETES_A_INSTALAR[@]}"
printf '\e[1;38;5;81m└────────────────────────────────────────────────────────────┘\e[0m\n'

backend_instalar "${PAQUETES_A_INSTALAR[@]}" || falla "falló la instalación de paquetes con $BACKEND (comprueba la conexión a internet)"
printf '%s\n' "$SISTEMA_LINUX:$ESC" > "$E/receta-aplicada" || falla "no se pudo registrar la receta instalada"

if [ "${#AUR_A_INSTALAR[@]}" -gt 0 ]; then
    paso "Instalando ayudantes de AUR desde aur.archlinux.org: ${AUR_A_INSTALAR[*]}"
    INST_AUR="$D/instalar-aur.sh"
    [ -x "$INST_AUR" ] || INST_AUR="$(dirname "$0")/instalar-aur.sh"
    [ -x "$INST_AUR" ] || INST_AUR="/usr/local/bin/instalar-aur"
    if [ -x "$INST_AUR" ]; then
        bash "$INST_AUR" "${AUR_A_INSTALAR[@]}" || printf '\e[1;38;5;214m✖ Aviso: puedes reintentar con: instalar-aur %s\e[0m\n' "${AUR_A_INSTALAR[*]}"
    fi
fi

paso "Ajustes del sistema"
elegido ssh && { [ -e /etc/ssh/ssh_host_ed25519_key ] || sudo ssh-keygen -A; }
sed -i '/^tty:x:5:/d' /etc/group
if [ -f /etc/pam.d/phosh ]; then
    printf "%s\n" "#%PAM-1.0" "auth       include      system-auth" "account    include      system-auth" "session    include      system-auth" > /etc/pam.d/phosh
fi
elegido zsh && {
    if [ "$ESC" != "sin-entorno" ]; then
        mkdir -p "/home/$N/.config/kitty"
        cp -rn /etc/skel/.config/kitty/. "/home/$N/.config/kitty/" 2>/dev/null || true
    fi
    mkdir -p "/home/$N/.config/starship"
    [ -f /etc/skel/.zshrc ] && cp -n /etc/skel/.zshrc "/home/$N/.zshrc" 2>/dev/null || true
    [ -f /etc/skel/.config/starship/starship.toml ] && cp -n /etc/skel/.config/starship/starship.toml "/home/$N/.config/starship/starship.toml" 2>/dev/null || true
    if command -v zsh >/dev/null 2>&1; then
        sed -i "s|/home/$N:.*|/home/$N:/usr/bin/zsh|" /etc/passwd 2>/dev/null || true
    fi
}
# Ajustar rutas reales del prefijo en ld.so.conf.d y preferencias de Firefox
if [ -n "$GLIBC_PREFIX" ]; then
    P_REL=$(echo "$GLIBC_PREFIX" | sed -E 's@^/data/(user/0|data)/@@')
    sed -i "s|@P@|$P_REL|g; s|dev.ben4shot.glibcprueba.[^/]*/files/[^/\"']*|$P_REL|g" /etc/ld.so.conf.d/android-prefijo.conf 2>/dev/null || true
    ldconfig 2>/dev/null || true
fi
FF=/usr/lib/firefox/browser/defaults/preferences
if [ -d "$FF" ]; then
    P_REL=$(echo "${GLIBC_PREFIX:-dev.ben4shot.glibcprueba.sdk36/files/archlinux}" | sed -E 's@^/data/(user/0|data)/@@')
    sed "s|/home/user/|/home/$N/|g; s|@P@|$P_REL|g; s|dev.ben4shot.glibcprueba.[^/]*/files/[^/\"',]*|$P_REL|g" "$D/firefox-android.js" > "$FF/android.js"
fi
[ -f /usr/share/applications/firefox.desktop ] &&
    sed 's|/usr/lib/firefox/firefox|/usr/local/bin/firefox|' /usr/share/applications/firefox.desktop \
        > ~/.local/share/applications/firefox.desktop

if [ -e $E/instalado ]; then
    printf '\n\e[1;38;5;48m┌────────────────────────────────────────────────────────────┐\e[0m\n'
    printf '\e[1;38;5;48m│\e[0m  \e[1;38;5;81mAJUSTES GUARDADOS CORRECTAMENTE\e[0m                           \e[1;38;5;48m│\e[0m\n'
    printf '\e[1;38;5;48m│\e[0m  \e[38;5;250mEl nuevo entorno se abrirá al reiniciar la sesión.\e[0m         \e[1;38;5;48m│\e[0m\n'
    printf '\e[1;38;5;48m└────────────────────────────────────────────────────────────┘\e[0m\n'
    exit 0
fi
touch $E/instalado
rm -f $E/instalando

printf '\n\e[1;38;5;48m┌────────────────────────────────────────────────────────────┐\e[0m\n'
printf '\e[1;38;5;48m│\e[0m  \e[1;38;5;81mINSTALACIÓN COMPLETADA CON ÉXITO\e[0m                          \e[1;38;5;48m│\e[0m\n'
printf '\e[1;38;5;48m│\e[0m  \e[38;5;250mIniciando el entorno de escritorio en la pantalla...\e[0m       \e[1;38;5;48m│\e[0m\n'
printf '\e[1;38;5;48m└────────────────────────────────────────────────────────────┘\e[0m\n'
sleep 2
