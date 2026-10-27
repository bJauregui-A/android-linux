#!/bin/bash
# Compila estatico-pie.c (static-pie, como el wine-preloader) con el toolchain de glibc/Dockerfile.
cd "$(dirname "$0")"
docker run --rm -u "$(id -u):$(id -g)" -v "$PWD:/w" -w /w glibc-cross \
  aarch64-linux-gnu-gcc -static-pie -fPIE -O2 -Wall -o estatico-pie-arm64 estatico-pie.c
