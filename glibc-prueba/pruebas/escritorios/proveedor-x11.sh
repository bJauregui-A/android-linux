#!/usr/bin/bash
# B11: el entorno de la app trae WAYLAND_DISPLAY=wayland-0 para todas las sesiones y GTK/Qt prefieren Wayland si
# existe: en una sesión X11 el panel, Thunar o xfdesktop se iban al compositor Wayland y no al servidor X11.
# El proveedor x11-directo debe dejar el entorno solo X11. Corre en el PC:  pruebas/escritorios/proveedor-x11.sh
cd "$(dirname "$0")/../.." || exit 1
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }
CONF=escritorios/proveedores/x11-directo/proveedor.conf

entorno=$(env -i PATH="$PATH" WAYLAND_DISPLAY=wayland-0 XDG_SESSION_TYPE=wayland bash -c ". $CONF; env")
caso "no deja WAYLAND_DISPLAY"        '! grep -q "^WAYLAND_DISPLAY=" <<<"$entorno"'
caso "GDK_BACKEND=x11"                'grep -qx "GDK_BACKEND=x11" <<<"$entorno"'
caso "QT_QPA_PLATFORM=xcb"            'grep -qx "QT_QPA_PLATFORM=xcb" <<<"$entorno"'
caso "XDG_SESSION_TYPE=x11"           'grep -qx "XDG_SESSION_TYPE=x11" <<<"$entorno"'

# El servidor X11 es de la app, no hijo de la sesión: sesion-android espera su socket ANTES de lanzar el escritorio
# (si no, xrdb/xfce4-session se conectan antes de que exista, mueren y el supervisor da "sin readiness").
SES=escritorios/sesion-android
l_espera=$(grep -n '\-S /tmp/.X11-unix/X0' $SES | head -1 | cut -d: -f1)
l_lanza=$(grep -n 'setsid /usr/bin/bash "$D/$id/sesion"' $SES | head -1 | cut -d: -f1)
caso "sesion-android espera el socket X11 antes de lanzar la sesión"  '[ -n "$l_espera" ] && [ -n "$l_lanza" ] && [ "$l_espera" -lt "$l_lanza" ]'
caso "ese socket no cuenta como resto de una sesión anterior"  'grep -q "x11_previos" $SES'

# El FALLO de un arranque anterior seguía en linux-session.estado y la vista lo mostraba como error del nuevo.
caso "sesion-android borra el estado de la sesión anterior al empezar"  \
  'l_borra=$(grep -n "rm -f \"\$estado_file\"" $SES | head -1 | cut -d: -f1); l_vacia=$(grep -n ": > \"\$boot_file\"" $SES | head -1 | cut -d: -f1); [ -n "$l_borra" ] && [ "$l_borra" -le "$((l_vacia + 1))" ]'

echo "fallas: $fallas"
[ $fallas -eq 0 ]
