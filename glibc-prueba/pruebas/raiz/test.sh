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

# TEMPORAL: chequeo de texto de C21. Borrar cuando C21 esté en en-telefono.sh
# (la prueba real corre en el teléfono; esto solo vigila el orden del código).
# C21: execveat con dirfd y '..' debe pasar por el resolvedor ANTES de armar
# /proc/self/fd/N/... (el '..' de /proc no se encierra).
EJ=$(awk '/case __NR_execveat:/{f=1} f{print} f&&/p = b2;/{exit}' $SRC/android-path.c)
a=$(grep -n 'raiz_resolver\|xlatd' <<<"$EJ" | head -1 | cut -d: -f1)
b=$(grep -n 'mcopy (q, "/proc/self/fd/' <<<"$EJ" | head -1 | cut -d: -f1)
if [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]; then echo "OK    C21 execveat: resolvedor antes de /proc/self/fd"
else echo "FALLA C21 execveat: android-path.c arma /proc/self/fd/N/<ruta> sin resolver '..'"; exit 1; fi
