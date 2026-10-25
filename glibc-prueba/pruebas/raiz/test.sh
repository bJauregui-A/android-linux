#!/bin/bash
# Pruebas C1-C12 de B26 en el PC: resolvedor aislado contra un árbol en /tmp.
set -e
AQUI=$(cd "$(dirname "$0")" && pwd)
SRC=$AQUI/../../glibc/glibc-2.43/sysdeps/unix/sysv/linux/aarch64
T=$(mktemp -d); trap 'rm -rf $T' EXIT
R=$T/instancia
mkdir -p $R/usr/lib $R/usr/bin $R/etc $R/home/user $T/otra-instancia/etc
ln -s usr/bin $R/bin
ln -s usr/lib $R/lib
ln -s $R/usr/lib $R/abs            # como los deja symlinkat: destino con prefijo
ln -s bucle2 $R/bucle1; ln -s bucle1 $R/bucle2
gcc -Wall -Wextra -I$SRC -o $T/t $AQUI/test_resolver.c $SRC/android-raiz.c
$T/t $R || exit 1
