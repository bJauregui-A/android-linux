# Instala los paquetes que usa sway/config y la valida con sway -C.
P=$APP_FILES/archlinux; L=$NATIVE_DIR/libldp.so
GLIBC_PREFIX=$P GLIBC_LOADER=$L HOME=/home/user PATH=/usr/bin LANG=C.UTF-8 TERM=dumb \
$L /usr/bin/bash -c '
  GLIBC_FAKEROOT=1 pacman -S --needed --noconfirm waybar fuzzel swaybg wl-clipboard cliphist autotiling jq ttf-jetbrains-mono-nerd kitty ttf-cascadia-code-nerd 2>&1 | tail -3
  pacman -Q waybar fuzzel swaybg wl-clipboard cliphist autotiling jq python-i3ipc ttf-jetbrains-mono-nerd kitty ttf-cascadia-code-nerd
  export XDG_RUNTIME_DIR=/run/user/$(id -u)
  sway -C -c ~/.config/sway/config 2>&1 | tail -10 && echo "config válida"
' 2>&1 | sed s/error/ERR/g; echo "=== fin"
