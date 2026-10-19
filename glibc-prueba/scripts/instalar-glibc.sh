#!/bin/bash
# Instala la glibc propia (glibc/salida) en la app de prueba:
#   - cargador -> jniLibs/libldp.so (recompila e instala el APK)
#   - bibliotecas de glibc propia en files/<prefijo>/usr/lib
#     (si el prefijo no existe, se crea como copia de files/glibc, el rootfs de preparar.sh)
# Uso: scripts/instalar-glibc.sh [sdk36|sdk28] [prefijo, por defecto arch]
set -e
V=${1:-sdk36}; PKG=dev.ben4shot.glibcprueba.$V; D=${2:-arch}
cd "$(dirname "$0")/.."
cp glibc/salida/usr/lib/ld-linux-aarch64.so.1 app/src/main/jniLibs/arm64-v8a/libldp.so
./gradlew -q assemble${V^}Debug
adb install -r app/build/outputs/apk/$V/debug/app-$V-debug.apk >/dev/null
T=$(mktemp -d)
(cd glibc/salida/usr/lib && tar -cf $T/libs.tar $(ls | grep -E '\.so(\.[0-9]+)+$|^ld-linux'))
adb push $T/libs.tar /data/local/tmp/glibc-libs.tar >/dev/null; rm -rf $T
adb shell "run-as $PKG sh -c 'cd files && { [ -d $D ] || cp -a glibc $D; } && tar -xf /data/local/tmp/glibc-libs.tar -C $D/usr/lib'"
adb shell rm /data/local/tmp/glibc-libs.tar
echo "instalado en $PKG: files/$D"
