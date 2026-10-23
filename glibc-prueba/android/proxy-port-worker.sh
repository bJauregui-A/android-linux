#!/system/bin/sh
# Worker universal ejecutado por toybox nc en cada conexión entrante
EXT_PORT="$1"
CONF="/data/local/tmp/proxy-ports.conf"

HOST=""
PORT=""

if [ -f "$CONF" ]; then
    # Buscar línea exacta que empiece por EXT_PORT
    LINEA=$(grep -E "^[[:space:]]*${EXT_PORT}[[:space:]]+" "$CONF" 2>/dev/null | head -n1)
    if [ -n "$LINEA" ]; then
        HOST=$(echo "$LINEA" | awk '{print $2}')
        PORT=$(echo "$LINEA" | awk '{print $3}')
    fi
fi

# Fallback para puerto 22 si no está en proxy-ports.conf pero existe ssh-proxy-target
if [ -z "$HOST" ] && [ "$EXT_PORT" = "22" ] && [ -f "/data/local/tmp/ssh-proxy-target" ]; then
    TARGET=$(cat /data/local/tmp/ssh-proxy-target 2>/dev/null)
    TARGET=${TARGET:-127.0.0.1:8022}
    HOST=${TARGET%:*}
    PORT=${TARGET#*:}
fi

[ -z "$HOST" ] && HOST="127.0.0.1"
[ -z "$PORT" ] && PORT="$EXT_PORT"

# Mapear 10.0.0.X a 127.0.0.X si viene con formato de subred virtual
case "$HOST" in
    10.*)
        B2=$(echo "$HOST" | cut -d. -f2)
        B3=$(echo "$HOST" | cut -d. -f3)
        B4=$(echo "$HOST" | cut -d. -f4 | cut -d/ -f1)
        HOST="127.$B2.$B3.$B4"
        ;;
esac

exec /system/bin/toybox nc "$HOST" "$PORT"
