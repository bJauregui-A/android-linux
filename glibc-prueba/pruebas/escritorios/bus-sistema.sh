#!/usr/bin/bash
# B11: cinnamon-session aborta con "Failed to connect to system bus" y GNOME con gsd-power: en la instancia no hay bus
# de sistema. dbus-daemon --system corre como usuario normal (probado en el teléfono), así que la sesión lo arranca
# cuando el escritorio declara el requisito "dbus-sistema" en REQUISITOS_SESION.
# Corre en el PC, con un dbus-daemon real y un socket temporal:  pruebas/escritorios/bus-sistema.sh
cd "$(dirname "$0")/../.." || exit 1
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }
ED=escritorios

requisitos() { ( . $ED/$1/escritorio.conf; echo " $REQUISITOS_SESION " ); }
for e in cinnamon gnome; do
  caso "$e declara el requisito dbus-sistema"  '[[ "$(requisitos $e)" == *" dbus-sistema "* ]]'
done
# No se toca lo que ya funciona: LXDE, MATE y GNOME Flashback arrancan sin bus de sistema.
for e in lxde mate gnome-flashback openbox xfce-x11 sway; do
  [ -f $ED/$e/escritorio.conf ] || continue
  caso "$e no lo pide (ya funciona sin él)"  '[[ "$(requisitos $e)" != *" dbus-sistema "* ]]'
done
caso "sesion-android sabe cumplir el requisito dbus-sistema"  'grep -q "dbus-sistema)" $ED/sesion-android'

for f in iniciar_bus_sistema detener_bus_sistema; do
  eval "$(sed -n "/^$f() {/,/^}/p" $ED/sesion-android)"
  type $f >/dev/null 2>&1 || { echo "FALLA no se encontró $f en $ED/sesion-android"; echo "fallas: $((fallas + 1))"; exit 1; }
done
d=$(mktemp -d); trap '[ -n "${BUS_SISTEMA_PID_ARCHIVO:-}" ] && detener_bus_sistema; rm -rf "$d"' EXIT
export XDG_RUNTIME_DIR=$d BUS_SISTEMA_SOCKET=$d/dbus/system_bus_socket BUS_SISTEMA_PID_ARCHIVO=$d/dbus.pid BUS_SISTEMA_LOG=$d/dbus.log

iniciar_bus_sistema
caso "iniciar_bus_sistema devuelve 0 y deja el socket"  '[ -S "$BUS_SISTEMA_SOCKET" ]'
caso "exporta DBUS_SYSTEM_BUS_ADDRESS hacia ese socket"  '[ "$DBUS_SYSTEM_BUS_ADDRESS" = "unix:path=$BUS_SISTEMA_SOCKET" ]'
caso "el bus responde"  'dbus-send --system --print-reply --dest=org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus.GetNameOwner string:org.freedesktop.DBus >/dev/null 2>&1'
pid=$(cat "$BUS_SISTEMA_PID_ARCHIVO" 2>/dev/null)
caso "guarda el pid del daemon, vivo"  '[ -n "$pid" ] && kill -0 "$pid" 2>/dev/null'

# cambiar_escritorio rehace la sesión con exec: llamarlo otra vez no debe arrancar un segundo daemon.
iniciar_bus_sistema
caso "idempotente: segunda llamada no cambia el pid"  '[ "$(cat "$BUS_SISTEMA_PID_ARCHIVO")" = "$pid" ]'
caso "idempotente: un solo dbus-daemon en ese socket"  '[ "$(pgrep -fc -- "--address=unix:path=$BUS_SISTEMA_SOCKET")" = 1 ]'

detener_bus_sistema
caso "detener_bus_sistema mata el daemon"  '! kill -0 "$pid" 2>/dev/null'
caso "detener_bus_sistema borra el archivo de pid"  '[ ! -e "$BUS_SISTEMA_PID_ARCHIVO" ]'
caso "detener_bus_sistema sin nada que detener no falla"  'detener_bus_sistema'

# Un socket viejo de una sesión muerta no cuenta: se arranca de verdad.
mkdir -p "$d/dbus"; rm -f "$BUS_SISTEMA_SOCKET"; python3 -c "import socket,sys; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1])" "$BUS_SISTEMA_SOCKET"
iniciar_bus_sistema
caso "con un socket muerto de antes, arranca uno nuevo que responde"  \
  'dbus-send --system --print-reply --dest=org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus.GetNameOwner string:org.freedesktop.DBus >/dev/null 2>&1'
detener_bus_sistema

# Sin dbus-daemon no hay nada que arrancar: devuelve 1 para que la sesión rechace el perfil con un motivo claro.
caso "sin dbus-daemon devuelve 1"  '( PATH=/nonexistent; ! iniciar_bus_sistema )'

echo "fallas: $fallas"
[ $fallas -eq 0 ]
