# /etc/profile.d/dbus-sesion.sh (lo copia scripts/subir-sway.sh): un bus de sesión
# D-Bus compartido en $XDG_RUNTIME_DIR/bus. Sin él, GLib intenta dbus-launch y
# waybar (gtkmm) aborta. Se arranca una vez; sway, la terminal y foot lo reutilizan.
if [ -n "$XDG_RUNTIME_DIR" ] && [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    export DBUS_SESSION_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/bus
    if ! dbus-send --session --dest=org.freedesktop.DBus --type=method_call / \
            org.freedesktop.DBus.Peer.Ping > /dev/null 2>&1; then
        rm -f "$XDG_RUNTIME_DIR/bus"
        dbus-daemon --session --address="$DBUS_SESSION_BUS_ADDRESS" --fork --nopidfile > /dev/null 2>&1
    fi
fi
