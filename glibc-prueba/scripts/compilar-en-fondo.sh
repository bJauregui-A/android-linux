#!/bin/bash
# Corre ~/<script> dentro del Arch de la app por run-as, en segundo plano y sin cerrar la
# app (a diferencia de correr.sh). Espera a que termine y muestra el resumen del log.
#   scripts/compilar-en-fondo.sh compilar-sway.sh
set -e
PKG=dev.ben4shot.glibcprueba.sdk36
S=$1
N=$(adb shell dumpsys package $PKG | grep -m1 legacyNativeLibraryDir | cut -d= -f2- | tr -d '\r')/arm64
F=/data/data/$PKG/files/archlinux
LOG=files/archlinux/home/user/${S%.sh}.log
adb shell "run-as $PKG sh -c 'rm -f $LOG.fin; cd $F; GLIBC_PREFIX=$F GLIBC_LOADER=$N/libldp.so HOME=/home/user PATH=/usr/bin LANG=C.UTF-8 TERM=dumb /system/bin/nohup $N/libldp.so /usr/bin/bash -c \"bash ~/$S > ~/${S%.sh}.log 2>&1; echo \\\$? > ~/${S%.sh}.log.fin\" > /dev/null 2>&1 &'"
echo "compilando $S (log en ~/${S%.sh}.log)..."
until adb shell "run-as $PKG cat $LOG.fin" 2>/dev/null | grep -q .; do sleep 10; done
echo "salida $(adb shell "run-as $PKG cat $LOG.fin" | tr -d '\r')"
adb shell "run-as $PKG cat $LOG" | grep -E "FAILED|rror:|ERROR|Dependency .* found: NO|listo|^real|símbolos|faltan" | grep -v "found: YES" | tail -40
