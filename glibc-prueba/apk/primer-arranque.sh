#!/usr/bin/bash
# Primer arranque, parte Linux (va en /usr/local/share/arch-android; lo lanza instalar.sh).
# Deja el Arch completo: usuario, llavero, paquetes (lo mínimo + lo que se elija en el menú: ssh,
# audio, Firefox, juegos...) y los ajustes que antes hacían a mano los scripts subir-*.sh.
# Se puede volver a correr (pacman --needed); --elegir vuelve a mostrar el menú.
D=/usr/local/share/arch-android
E=/var/lib/arch-android
paso() { printf '\n\e[1;36m==> %s\e[0m\n' "$*"; }
falla() {
    printf '\n\e[1;31m%s\e[0m\n' "$*"
    read -rp "Enter para reintentar (Ctrl+C sale a la terminal)... " _
    exec bash "$0"
}
lista() { for g; do sed 's/#.*//' "$D/paquetes-$g.txt"; done | tr -s ' \n' '  '; }

printf '\e[1mInstalando Arch Linux\e[0m (lo mínimo baja ~500 MB, más lo que elijas; no cierres la app)\n'

# Usuario y nombre del dispositivo (una vez; quedan en $E/usuario y /etc/hostname, que la app
# y la glibc leen: TerminalService.usuario(), uname/gethostname desde la 0019)
if [ ! -s $E/usuario ]; then
    while :; do
        read -rp $'\nNombre de usuario (minúsculas, números, - y _): ' N
        [[ $N =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] && [ "$N" != root ] && break
        echo "no vale: empieza con letra minúscula o _, sin espacios ni mayúsculas"
    done
    echo "$N" > $E/usuario
fi
N=$(cat $E/usuario)
if [ ! -s /etc/hostname ]; then
    # Sugerido: el modelo de Android en minúsculas ("Redmi 15 5G" → redmi-15-5g)
    S=$(echo "${ANDROID_MODELO:-android}" | tr 'A-Z ' 'a-z-' | tr -cd 'a-z0-9-' | sed 's/^-*//; s/-*$//')
    while :; do
        read -rp "Nombre del dispositivo [${S:-android}]: " H
        H=${H:-${S:-android}}
        [[ $H =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]] && break
        echo "no vale: letras, números y guiones (sin espacios)"
    done
    echo "$H" > /etc/hostname
fi
U=$(id -u); G=$(id -g)
grep -q "^$N:" /etc/passwd || echo "$N:x:$U:$G:$N:/home/$N:/usr/bin/zsh" >> /etc/passwd
grep -q "^$N:" /etc/group || echo "$N:x:$G:" >> /etc/group
# El home con las configs de /etc/skel (sway, waybar, kitty, zsh...)
if [ ! -d /home/$N/.config ]; then
    mkdir -p /home/$N
    cp -a /etc/skel/. /home/$N/
fi
rmdir /home/user 2>/dev/null  # la app lo crea antes de saber el nombre
export HOME=/home/$N USER=$N LOGNAME=$N
cd ~

if [ ! -e $E/base-lista ]; then
    paso "Scripts de instalación de la base"
    for d in /var/lib/pacman/local/*/; do
        [ -f $d/install ] || continue
        ver=$(sed -n "/^%VERSION%/{n;p}" $d/desc)
        (cd / && GLIBC_FAKEROOT=1 HOME=/root bash -c ". $d/install; declare -F post_install >/dev/null && post_install $ver" > /dev/null 2>&1)
    done
    paso "Llavero de pacman"
    sudo pacman-key --init > /dev/null 2>&1 && sudo pacman-key --populate archlinuxarm || falla "falló pacman-key"
    touch $E/base-lista
fi

# Opcionales: menú una vez (lo elegido queda en $E/opcionales). Para elegir de nuevo e instalar
# más después: bash /usr/local/share/arch-android/primer-arranque.sh --elegir
[ "$1" = --elegir ] && rm -f $E/opcionales
GRUPOS=(ssh audio firefox juegos desarrollo adb utilidades)
TEXTOS=("SSH: servidor en el puerto 8022 (~5 MB)"
        "audio: PipeWire → altavoz de Android (~25 MB)"
        "Firefox con GPU (~250 MB)"
        "juegos: Steam ARM64, Proton directo, Lutris (~1 GB)"
        "desarrollo: gcc, meson, git, gdb, strace (~400 MB)"
        "adb local sin PC: depuración inalámbrica (adb-conectar) (~10 MB)"
        "utilidades: htop, grim (capturas), unzip, wget (~5 MB)")
MARCA=(1 1 0 0 0 0 0)
if [ ! -e $E/opcionales ]; then
    while :; do
        printf '\n\e[1mQué instalar\e[0m (el escritorio, kitty, zsh y los gráficos van siempre):\n'
        for i in "${!GRUPOS[@]}"; do
            [ "${MARCA[$i]}" = 1 ] && x=x || x=' '
            printf '  [%s] %d  %s\n' "$x" $((i + 1)) "${TEXTOS[$i]}"
        done
        read -rp "Números para marcar/desmarcar (ej: 3 4), Enter para seguir: " r
        [ -z "$r" ] && break
        for n in $r; do
            [[ $n =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le ${#GRUPOS[@]} ] &&
                MARCA[$((n - 1))]=$((1 - MARCA[n - 1]))
        done
    done
    for i in "${!GRUPOS[@]}"; do [ "${MARCA[$i]}" = 1 ] && echo "${GRUPOS[$i]}"; done > $E/opcionales
fi
elegido() { grep -qx "$1" $E/opcionales; }
grupos="escritorio $(tr '\n' ' ' < $E/opcionales)"

paso "Paquetes: $grupos"
# El mirror corta descargas de vez en cuando: reintentar solo (lo bajado queda en la caché)
for i in 1 2 3; do
    sudo pacman -Syu --needed --noconfirm $(lista $grupos) && break
    [ $i = 3 ] && falla "falló pacman 3 veces (¿sin internet?)"
    printf '\n\e[33mfalló la descarga, reintento %d de 2...\e[0m\n' $i
    sleep 3
done

paso "Ajustes"
# sshd (sway lo arranca): claves de host. Sin grupo tty, sshd no toca el pty (SELinux lo niega)
elegido ssh && { [ -e /etc/ssh/ssh_host_ed25519_key ] || sudo ssh-keygen -A; }
sed -i '/^tty:x:5:/d' /etc/group
# Firefox: rutas del prefijo para el sandbox y el .desktop con el envoltorio de GPU
FF=/usr/lib/firefox/browser/defaults/preferences
[ -d $FF ] && sed "s|/home/user/|/home/$N/|g" $D/firefox-android.js > $FF/android.js
[ -f /usr/share/applications/firefox.desktop ] &&
    sed 's|/usr/lib/firefox/firefox|/usr/local/bin/firefox|' /usr/share/applications/firefox.desktop \
        > ~/.local/share/applications/firefox.desktop

if elegido juegos && [ ! -e $E/juegos-listos ]; then
    paso "Juegos"
    bash $D/juegos.sh || falla "falló la instalación de los juegos"
    touch $E/juegos-listos
fi

touch $E/instalado
rm -f $E/instalando
paso "Listo: abriendo el escritorio"
sleep 2
