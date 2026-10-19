#!/bin/bash
# Copia la config de sway del repo (sway/: config, scripts, waybar, fuzzel, kitty) a ~/.config del Arch de la app,
# y sway/dbus-sesion.sh a /etc/profile.d (bus de sesión D-Bus: waybar lo necesita).
# La primera vez respalda la config anterior en ~/.config/sway/config.anterior.
# Paquetes que usa: TIEMPO=600 scripts/correr.sh sdk36 scripts/test-sway-config.sh (instala y valida).
# Se aplica al reiniciar sway (cerrar la app o SUPER+Delete y volver a abrir el ícono).
set -e
cd "$(dirname "$0")/.."
PKG=dev.ben4shot.glibcprueba.sdk36
C=files/archlinux/home/user/.config
adb shell "run-as $PKG mkdir -p $C/sway $C/waybar $C/fuzzel $C/kitty"
adb shell "run-as $PKG sh -c '[ -e $C/sway/config.anterior ] || cp $C/sway/config $C/sway/config.anterior 2>/dev/null || true'"
copiar() { adb push "$1" /data/local/tmp/ >/dev/null
           adb shell "run-as $PKG cp /data/local/tmp/$(basename $1) $2 && rm /data/local/tmp/$(basename $1)"; }
for f in sway/config sway/opacidad.py sway/ventanas.sh sway/escritorio-vacio.sh sway/atajos.sh; do copiar $f $C/sway/; done
copiar sway/waybar/config.jsonc $C/waybar/
copiar sway/waybar/style.css $C/waybar/
copiar sway/fuzzel/fuzzel.ini $C/fuzzel/
for f in sway/kitty/*.conf; do copiar $f $C/kitty/; done
copiar sway/dbus-sesion.sh files/archlinux/etc/profile.d/
adb shell "run-as $PKG chmod 755 $C/sway/ventanas.sh $C/sway/escritorio-vacio.sh $C/sway/atajos.sh"
echo "config de sway copiada"
