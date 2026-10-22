#!/bin/bash
# Clona e instala yay o paru desde aur.archlinux.org directamente en el Arch del teléfono vía ADB
set -e
cd "$(dirname "$0")/.."

PKG=dev.ben4shot.glibcprueba.sdk36
A=files/archlinux

TARGETS=${*:-yay-bin}

echo "==> Copiando apk/instalar-aur.sh al prefijo de Arch..."
adb push apk/instalar-aur.sh /data/local/tmp/instalar-aur.sh >/dev/null
adb shell "run-as $PKG cp /data/local/tmp/instalar-aur.sh $A/usr/local/bin/instalar-aur && chmod 755 $A/usr/local/bin/instalar-aur && rm /data/local/tmp/instalar-aur.sh"

echo "==> Asegurando base-devel y git con pacman..."
adb shell "run-as $PKG sh -c 'cd $A && HOME=/home/user PATH=/usr/local/bin:/usr/bin:/bin sudo pacman -S --needed --noconfirm base-devel git'"

for t in $TARGETS; do
    echo "==> Instalando $t desde aur.archlinux.org..."
    adb shell "run-as $PKG sh -c 'cd $A && HOME=/home/user PATH=/usr/local/bin:/usr/bin:/bin /usr/local/bin/instalar-aur $t'"
done

echo "==> Listo."
