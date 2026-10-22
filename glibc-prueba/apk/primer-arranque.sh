#!/usr/bin/bash
# Primer arranque, parte Linux (va en /usr/local/share/arch-android; lo lanza instalar.sh).
# Deja el Arch completo: usuario, llavero, paquetes (lo mínimo + lo que se elija en el menú: ssh,
# audio, Firefox, juegos...) y los ajustes que antes hacían a mano los scripts subir-*.sh.
# Se puede volver a correr (pacman --needed); --elegir vuelve a mostrar el menú.
D=/usr/local/share/arch-android
E=/var/lib/arch-android

# Funciones de estilo
paso() {
    printf '\n\e[1;38;5;81m┌─ %s\e[0m\n' "$*"
}
falla() {
    printf '\n\e[1;38;5;196m✖ Error: %s\e[0m\n' "$*"
    read -rp "Presiona Enter para reintentar (Ctrl+C para salir a la terminal)... " _
    exec bash "$0"
}
lista() { for g; do sed 's/#.*//' "$D/paquetes-$g.txt"; done | tr -s ' \n' '  '; }

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
        printf '\e[1;38;5;111m│\e[0m  \e[1;38;5;48m❯\e[0m Nombre de usuario (letras minúsculas, números, - y _) [user]: '
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
        printf '\e[1;38;5;111m│\e[0m  \e[1;38;5;48m❯\e[0m Nombre del dispositivo (hostname) [%s]: ' "${S:-android}"
        read -r H
        H=${H:-${S:-android}}
        [[ $H =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]] && break
        printf '\e[1;38;5;111m│\e[0m  \e[38;5;214m✖ Inválido: solo letras, números y guiones (sin espacios)\e[0m\n'
    done
    echo "$H" > /etc/hostname
    printf '\e[1;38;5;111m└────────────────────────────────────────────────────────────┘\e[0m\n'
fi
U=$(id -u); G=$(id -g)
grep -q "^$N:" /etc/passwd || echo "$N:x:$U:$G:$N:/home/$N:/usr/bin/zsh" >> /etc/passwd
grep -q "^$N:" /etc/group || echo "$N:x:$G:" >> /etc/group
# El home con las configs de /etc/skel (sway, waybar, kitty, zsh...)
if [ ! -d /home/$N/.config ]; then
    mkdir -p /home/$N
    cp -a /etc/skel/. /home/$N/
fi
rmdir /home/user 2>/dev/null

# Contraseña del usuario: la piden el bloqueo de pantalla de los escritorios (KDE, COSMIC, phosh...),
# SSH y las ventanas de autenticación. Se guarda su hash (SHA-512) en /etc/shadow.
contrasena_definida() { grep -q "^$N:[^!*:][^:]*:" /etc/shadow 2>/dev/null; }
pedir_contrasena() {
    local p1 p2 h
    printf '\n\e[1;38;5;111m┌─ [2/4] Seguridad y Autenticación ──────────────────────────┐\e[0m\n'
    printf '\e[1;38;5;111m│\e[0m  Configura la contraseña de \e[1;38;5;48m%s\e[0m (sudo, SSH, pantalla de bloqueo):\n' "$N"
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
    paso "Inicializando base y paquetes de sistema"
    for d in /var/lib/pacman/local/*/; do
        [ -f $d/install ] || continue
        ver=$(sed -n "/^%VERSION%/{n;p}" $d/desc)
        (cd / && GLIBC_FAKEROOT=1 HOME=/root bash -c ". $d/install; declare -F post_install >/dev/null && post_install $ver" > /dev/null 2>&1)
    done
    paso "Configurando llavero de pacman y certificados SSL"
    sudo pacman-key --init > /dev/null 2>&1 && sudo pacman-key --populate archlinuxarm || falla "falló pacman-key"
    sudo update-ca-trust > /dev/null 2>&1 || true
    touch $E/base-lista
fi

# Escritorio: uno, elegido una vez ($E/escritorio; lo arranca /usr/local/bin/sesion-android)
[ "$1" = --elegir ] && rm -f $E/opcionales $E/escritorio
[ "$1" = --escritorio ] && rm -f $E/escritorio
ED=$D/escritorios
if [ ! -s $E/escritorio ]; then
    mapfile -t IDS < <(grep -v '^#' $ED/orden)
    printf '\n\e[1;38;5;111m┌────────────────────────────────────────────────────────────┐\e[0m\n'
    printf '\e[1;38;5;111m│\e[0m  \e[1;38;5;81m[3/4] Selección de Entorno de Escritorio\e[0m                  \e[1;38;5;111m│\e[0m\n'
    printf '\e[1;38;5;111m│\e[0m  \e[38;5;245m14 entornos validados con GPU Adreno (Turnip + Zink)\e[0m       \e[1;38;5;111m│\e[0m\n'
    printf '\e[1;38;5;111m├────────────────────────────────────────────────────────────┤\e[0m\n'
    for i in "${!IDS[@]}"; do
        (. $ED/${IDS[$i]}/escritorio.conf
         if [ "$ESTADO" = probado ]; then
             e=$'\e[1;38;5;48m● PROBADO\e[0m'
         else
             e=$'\e[38;5;214m○ experimental\e[0m'
         fi
         # Nombres destacados con color cian brillante
         printf '\e[1;38;5;111m│\e[0m  \e[1;38;5;81m[%2d]\e[0m \e[1;38;5;51m%-14s\e[0m %-18s \e[38;5;248m%-18s\e[0m\e[1;38;5;111m│\e[0m\n' \
             $((i + 1)) "$NOMBRE" "$e" "($TAMANO)")
    done
    printf '\e[1;38;5;111m└────────────────────────────────────────────────────────────┘\e[0m\n'
    while :; do
        printf '\e[1;38;5;48m❯\e[0m Selecciona un número [1-%d, por defecto 1 = sway]: ' "${#IDS[@]}"
        read -r r
        r=${r//[$'\r ']/}
        r=${r:-1}
        [[ $r =~ ^[0-9]+$ ]] && [ "$r" -ge 1 ] && [ "$r" -le ${#IDS[@]} ] && break
        printf '\e[38;5;214m✖ Número fuera de rango (1 a %d)\e[0m\n' "${#IDS[@]}"
    done
    echo "${IDS[r - 1]}" > $E/escritorio
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

GRUPOS=(ssh audio firefox desarrollo adb utilidades)
TEXTOS=("SSH: Servidor seguro en el puerto 8022 (~5 MB)"
        "Audio: PipeWire → Altavoz Android vía AudioTrack (~25 MB)"
        "Firefox con aceleración GPU WebRender (~250 MB)"
        "Desarrollo: gcc, meson, git, gdb, strace (~400 MB)"
        "ADB local sin PC: depuración inalámbrica (~10 MB)"
        "Utilidades: htop, grim (capturas), unzip, wget (~5 MB)")
MARCA=(1 1 0 0 0 0)

if [ ! -e $E/opcionales ]; then
    idx_actual=0
    num_opciones=${#GRUPOS[@]}

    dibujar_menu_opcionales() {
        printf '\033[2J\033[H'
        printf '\e[1;38;5;111m┌────────────────────────────────────────────────────────────┐\e[0m\n'
        printf '\e[1;38;5;111m│\e[0m  \e[1;38;5;81m[4/4] Módulos y Paquetes Opcionales\e[0m                       \e[1;38;5;111m│\e[0m\n'
        printf '\e[1;38;5;111m│\e[0m  \e[38;5;245mUsa ↑/↓ para moverte, Enter/Espacio para marcar o enviar\e[0m  \e[1;38;5;111m│\e[0m\n'
        printf '\e[1;38;5;111m├────────────────────────────────────────────────────────────┤\e[0m\n'
        for i in "${!GRUPOS[@]}"; do
            if [ "${MARCA[$i]}" = 1 ]; then
                chk=$'\e[1;38;5;48m[✔]\e[0m'
            else
                chk=$'\e[38;5;245m[ ]\e[0m'
            fi
            if [ "$i" -eq "$idx_actual" ]; then
                printf '\e[1;38;5;111m│\e[0m \e[1;38;5;51m❯\e[0m %s \e[1;38;5;15m%-54s\e[0m\e[1;38;5;111m│\e[0m\n' "$chk" "${TEXTOS[$i]}"
            else
                printf '\e[1;38;5;111m│\e[0m   %s \e[38;5;250m%-54s\e[0m\e[1;38;5;111m│\e[0m\n' "$chk" "${TEXTOS[$i]}"
            fi
        done
        printf '\e[1;38;5;111m├────────────────────────────────────────────────────────────┤\e[0m\n'
        if [ "$idx_actual" -eq "$num_opciones" ]; then
            printf '\e[1;38;5;111m│\e[0m \e[1;38;5;51m❯\e[0m  \e[1;38;5;48m[ ✔ ENVIAR Y CONTINUAR (SUBMIT) ]\e[0m                        \e[1;38;5;111m│\e[0m\n'
        else
            printf '\e[1;38;5;111m│\e[0m    \e[38;5;245m[   Enviar y continuar (Submit)   ]\e[0m                        \e[1;38;5;111m│\e[0m\n'
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
        elif [ "$tecla" = "" ] || [ "$tecla" = $'\n' ] || [ "$tecla" = $'\r' ]; then
            if [ "$idx_actual" -eq "$num_opciones" ]; then
                break
            else
                MARCA[idx_actual]=$((1 - MARCA[idx_actual]))
            fi
        elif [ "$tecla" = " " ]; then
            if [ "$idx_actual" -eq "$num_opciones" ]; then
                break
            else
                MARCA[idx_actual]=$((1 - MARCA[idx_actual]))
            fi
        elif [ "$tecla" = "s" ] || [ "$tecla" = "S" ]; then
            break
        elif [[ "$tecla" =~ ^[1-6]$ ]]; then
            val=$((tecla - 1))
            MARCA[val]=$((1 - MARCA[val]))
        fi
    done

    for i in "${!GRUPOS[@]}"; do [ "${MARCA[$i]}" = 1 ] && echo "${GRUPOS[$i]}"; done > $E/opcionales
fi
elegido() { grep -qx "$1" $E/opcionales; }
grupos="escritorio $(tr '\n' ' ' < $E/opcionales)"

printf '\n\e[1;38;5;81m┌─ Descarga e instalación de paquetes pacman ────────────────┐\e[0m\n'
printf '\e[1;38;5;81m│\e[0m  Módulos: \e[1;38;5;48m%s\e[0m | Escritorio: \e[1;38;5;48m%s\e[0m\n' "$grupos" "$ESC"
printf '\e[1;38;5;81m└────────────────────────────────────────────────────────────┘\e[0m\n'

for i in 1 2 3; do
    sudo pacman -Syu --needed --noconfirm $(lista $grupos) $(sed 's/#.*//' $ED/$ESC/paquetes.txt) && break
    [ $i = 3 ] && falla "falló pacman 3 veces consecutivas (comprueba la conexión a internet)"
    printf '\n\e[38;5;214m✖ Falló la descarga, reintento %d de 2...\e[0m\n' $i
    sleep 3
done
printf '%s\n' "$SISTEMA_LINUX:$ESC" > "$E/receta-aplicada" || falla "no se pudo registrar la receta instalada"

paso "Ajustes del sistema"
elegido ssh && { [ -e /etc/ssh/ssh_host_ed25519_key ] || sudo ssh-keygen -A; }
sed -i '/^tty:x:5:/d' /etc/group
FF=/usr/lib/firefox/browser/defaults/preferences
[ -d $FF ] && sed "s|/home/user/|/home/$N/|g" $D/firefox-android.js > $FF/android.js
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
