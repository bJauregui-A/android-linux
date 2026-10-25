#!/bin/bash
# Compila estatico.c (C19/C21 de B26) para aarch64 con el toolchain de glibc/Dockerfile.
cd "$(dirname "$0")"
docker run --rm -u "$(id -u):$(id -g)" -v "$PWD:/w" -w /w glibc-cross \
  aarch64-linux-gnu-gcc -static -O2 -Wall -o estatico-arm64 estatico.c
