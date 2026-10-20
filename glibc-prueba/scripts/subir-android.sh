#!/bin/bash
# Integración con Android (android/): android-abrir, xdg-open y android-notificaciones a
# /usr/local/bin, el servicio D-Bus de notificaciones (~/.local/share/dbus-1/services), el .desktop
# y los programas por defecto (links → Android) en ~/.local/share/applications y ~/.config.
# Un mimeapps.list que ya exista no se pisa (avisa).
set -e
cd "$(dirname "$0")/.."
PKG=dev.ben4shot.glibcprueba.sdk36
A=files/archlinux
copiar() { adb push "$1" /data/local/tmp/ >/dev/null
           adb shell "run-as $PKG cp /data/local/tmp/$(basename $1) $2 && rm /data/local/tmp/$(basename $1)"; }
adb shell "run-as $PKG mkdir -p $A/usr/local/bin $A/home/user/.local/share/applications $A/home/user/.local/share/dbus-1/services $A/home/user/.config"
copiar android/android-abrir $A/usr/local/bin/
copiar android/xdg-open $A/usr/local/bin/
copiar android/android-notificaciones $A/usr/local/bin/
adb shell "run-as $PKG chmod 755 $A/usr/local/bin/android-abrir $A/usr/local/bin/xdg-open $A/usr/local/bin/android-notificaciones"
copiar android/org.freedesktop.Notifications.service $A/home/user/.local/share/dbus-1/services/
copiar android/android-abrir.desktop $A/home/user/.local/share/applications/
copiar android/mimeapps.list $A/tmp/
adb shell "run-as $PKG sh -c 'cd $A; if [ -e home/user/.config/mimeapps.list ]; then
  echo \"ya hay ~/.config/mimeapps.list: agregar a mano las líneas de android/mimeapps.list\";
  else cp tmp/mimeapps.list home/user/.config/; fi; rm tmp/mimeapps.list'"
echo "integración con Android copiada"
