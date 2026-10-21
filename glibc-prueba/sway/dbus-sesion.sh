# /etc/profile.d/dbus-sesion.sh: comparte el bus D-Bus de la sesión gráfica con terminales
# de rescate. sesion-android crea y destruye ese bus con dbus-run-session; no lo reemplazamos.
if [ -n "$XDG_RUNTIME_DIR" ]; then
    if [ -n "$DBUS_SESSION_BUS_ADDRESS" ] && \
            dbus-send --session --dest=org.freedesktop.DBus --type=method_call / \
                org.freedesktop.DBus.Peer.Ping > /dev/null 2>&1; then
        return 0
    fi
    unset DBUS_SESSION_BUS_ADDRESS
    bus_file="$XDG_RUNTIME_DIR/arch-android-bus"
    if [ -s "$bus_file" ]; then
        DBUS_SESSION_BUS_ADDRESS=$(cat "$bus_file")
        export DBUS_SESSION_BUS_ADDRESS
        if dbus-send --session --dest=org.freedesktop.DBus --type=method_call / \
                org.freedesktop.DBus.Peer.Ping > /dev/null 2>&1; then
            return 0
        fi
    fi
    # Durante el arranque gráfico el supervisor crea el bus al entrar en sesion-android.
    if [ -n "$ARCH_ANDROID_SESSION_START" ]; then return 0; fi

    # Compatibilidad para la terminal de rescate cuando no hay escritorio activo.
    DBUS_SESSION_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/bus
    export DBUS_SESSION_BUS_ADDRESS
    if ! dbus-send --session --dest=org.freedesktop.DBus --type=method_call / \
            org.freedesktop.DBus.Peer.Ping > /dev/null 2>&1; then
        rm -f "$XDG_RUNTIME_DIR/bus"
        dbus-daemon --session --address="$DBUS_SESSION_BUS_ADDRESS" --fork --nopidfile > /dev/null 2>&1
    fi
fi
