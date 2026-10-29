#!/bin/bash
# Compila pila.c y bss.c (B17) para aarch64 sin libc, con el toolchain de glibc/Dockerfile.
# bss.c va sin -Wl,-N: lo que prueba es justo el segmento solo-.bss que -N evita.
cd "$(dirname "$0")"
docker run --rm -u "$(id -u):$(id -g)" -v "$PWD:/w" -w /w glibc-cross bash -c '
  aarch64-linux-gnu-gcc -static -nostdlib -Wl,-N -ffreestanding -fno-stack-protector -mno-outline-atomics -O1 -Wall -o pila-arm64 pila.c &&
  aarch64-linux-gnu-gcc -static -nostdlib -ffreestanding -fno-stack-protector -O1 -Wall -o bss-arm64 bss.c'
