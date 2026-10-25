#!/bin/bash
# Compila service y service-daemon.
#   ./compilar.sh                 ARM64 con Docker (glibc-cross), deja los binarios en esta carpeta
#   ./compilar.sh --local [dir]   gcc del PC, para probar con SERVICE_ROOT (dir por defecto: ./build-local)
set -euo pipefail
cd "$(dirname "$0")"

CLI="service.c cliente.c salida.c common.c"
DEMONIO="service-daemon.c proceso.c unidad.c habilitados.c common.c"

if [ "${1:-}" = "--local" ]; then
    out="${2:-build-local}"
    mkdir -p "$out"
    gcc -O2 -Wall -o "$out/service" $CLI
    gcc -O2 -Wall -o "$out/service-daemon" $DEMONIO
    ls -lh "$out/service" "$out/service-daemon"
    exit 0
fi

docker run --rm -u "$(id -u):$(id -g)" -v "$PWD/../..:/w" -w /w/glibc-prueba/supervisor glibc-cross bash -c "
    aarch64-linux-gnu-gcc -O2 -Wall -o service $CLI
    aarch64-linux-gnu-gcc -O2 -Wall -o service-daemon $DEMONIO
"
ls -lh service service-daemon
