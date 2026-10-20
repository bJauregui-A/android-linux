#!/usr/bin/bash
# Primer arranque, parte Linux (va en /usr/local/share/arch-android; lo lanza instalar.sh).
# Deja el Arch completo: usuario, llavero, paquetes (escritorio, Firefox, desarrollo y, si se
# elige, juegos), sshd y los ajustes que antes hacían a mano los scripts subir-*.sh.
# Se puede volver a correr (pacman --needed): bash /usr/local/share/arch-android/primer-arranque.sh
D=/usr/local/share/arch-android
E=/var/lib/arch-android
paso() { printf '\n\e[1;36m==> %s\e[0m\n' "$*"; }
falla() {
    printf '\n\e[1;31m%s\e[0m\n' "$*"
    read -rp "Enter para reintentar (Ctrl+C sale a la terminal)... " _
    exec bash "$0"
}
lista() { for g; do sed 's/#.*//' "$D/paquetes-$g.txt"; done | tr -s ' \n' '  '; }

printf '\e[1mInstalando Arch Linux\e[0m (la primera vez baja ~1–2 GB; no cierres la app)\n'

U=$(id -u); G=$(id -g)
grep -q "^user:" /etc/passwd || echo "user:x:$U:$G:Usuario:/home/user:/bin/bash" >> /etc/passwd
grep -q "^user:" /etc/group || echo "user:x:$G:" >> /etc/group

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

if [ ! -e $E/juegos ]; then
    printf '\n¿Instalar también los juegos? Steam ARM64, Proton directo y Lutris (~1 GB más).\n'
    read -rp "[s/N] " r
    case $r in [sSyY]*) echo si ;; *) echo no ;; esac > $E/juegos
fi
grupos="escritorio firefox desarrollo"
[ "$(cat $E/juegos)" = si ] && grupos="$grupos juegos"

paso "Paquetes: $grupos"
sudo pacman -Syu --needed --noconfirm $(lista $grupos) || falla "falló pacman (¿sin internet?)"

paso "Ajustes"
# sshd (sway lo arranca): claves de host. Sin grupo tty, sshd no toca el pty (SELinux lo niega)
[ -e /etc/ssh/ssh_host_ed25519_key ] || sudo ssh-keygen -A
sed -i '/^tty:x:5:/d' /etc/group
# Firefox: rutas del prefijo para el sandbox y el .desktop con el envoltorio de GPU
FF=/usr/lib/firefox/browser/defaults/preferences
[ -d $FF ] && cp $D/firefox-android.js $FF/android.js
[ -f /usr/share/applications/firefox.desktop ] &&
    sed 's|/usr/lib/firefox/firefox|/usr/local/bin/firefox|' /usr/share/applications/firefox.desktop \
        > ~/.local/share/applications/firefox.desktop

if [ "$(cat $E/juegos)" = si ] && [ ! -e $E/juegos-listos ]; then
    paso "Juegos"
    bash $D/juegos.sh || falla "falló la instalación de los juegos"
    touch $E/juegos-listos
fi

touch $E/instalado
rm -f $E/instalando
paso "Listo: abriendo el escritorio"
sleep 2
