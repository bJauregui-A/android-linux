#!/bin/bash
# Compila service y service-daemon para ARM64 usando Docker (glibc-cross)
set -euo pipefail
cd "$(dirname "$0")"

docker run --rm -u "$(id -u):$(id -g)" -v "$PWD/../..:/w" -w /w/glibc-prueba/supervisor glibc-cross bash -c "
    aarch64-linux-gnu-gcc -O2 -Wall -o service service.c
    aarch64-linux-gnu-gcc -O2 -Wall -o service-daemon service-daemon.c
"
ls -lh service service-daemon
