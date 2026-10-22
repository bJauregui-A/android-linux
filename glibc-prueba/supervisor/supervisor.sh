#!/bin/sh
# Auto-arranque del demonio supervisor en segundo plano para sesiones interactivas
if [ -x /usr/local/bin/service-daemon ]; then
    SOCK="${XDG_RUNTIME_DIR:-/run}/supervisor.sock"
    if [ ! -S "$SOCK" ] && [ ! -S /run/supervisor.sock ] && [ ! -S /tmp/supervisor.sock ]; then
        /usr/local/bin/service-daemon > /dev/null 2>&1 &
    fi
fi

