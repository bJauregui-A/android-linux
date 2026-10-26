#!/bin/bash
# B11: crea una instancia de prueba y espera a que termine de instalarse, sin tocar la pantalla del teléfono.
#   crear-en-telefono.sh <arch|debian> <nombre> <escritorio> [opcionales,separados,por,comas] [limite-seg]
# Imprime el id de la instancia. Códigos: 0 instalada; 2 pedido inválido; 3 no llegó al app o no terminó
# (la instalación sigue en el teléfono); 124 por límite de tiempo.
# Requiere una APK de depuración (ReceptorCrearInstancia). Usuario y contraseña son de prueba, no reales:
#   PRUEBA_USUARIO (prueba) y PRUEBA_CLAVE (clave-de-prueba-x11); al app solo llega el hash.
APP=${APP:-dev.ben4shot.glibcprueba.sdk36}
distro=$1; nombre=$2; escritorio=$3; opcionales=${4:-}; limite=${5:-3600}
[ -n "$distro" ] && [ -n "$nombre" ] && [ -n "$escritorio" ] ||
  { echo "uso: $0 <arch|debian> <nombre> <escritorio> [opcionales] [limite]" >&2; exit 2; }
[[ $limite =~ ^[0-9]+$ ]] || { echo "limite debe ser un número de segundos" >&2; exit 2; }
adb get-state >/dev/null 2>&1 || { echo "adb: no hay teléfono conectado" >&2; exit 3; }
usuario=${PRUEBA_USUARIO:-prueba}; clave=${PRUEBA_CLAVE:-clave-de-prueba-x11}
hash=$(printf '%s' "$clave" | openssl passwd -6 -stdin) || { echo "falta openssl" >&2; exit 2; }

r=$(adb shell "am broadcast -n $APP/dev.ben4shot.glibcprueba.ReceptorCrearInstancia -a dev.ben4shot.glibcprueba.CREAR_INSTANCIA \
  --es distro '$distro' --es nombre '$nombre' --es escritorio '$escritorio' --es opcionales '$opcionales' \
  --es usuario '$usuario' --es hash '$hash'" 2>&1)
id=$(sed -n 's/.*data="\(.*\)".*/\1/p' <<<"$r")
case $id in
  ''|error*) echo "no se creó la instancia: ${id:-el broadcast no llegó (¿APK de depuración instalada?)}" >&2; exit 3;;
esac
echo "instancia: $id" >&2

ra() { adb shell run-as "$APP" "$@" 2>/dev/null; }
estado=files/instancias/$id/var/lib/linux-android
fin=$((SECONDS + limite)); ultimo=0
while [ $SECONDS -lt $fin ]; do
  if [ -n "$(ra ls "$estado/instalado")" ]; then echo "$id"; exit 0; fi
  if [ $((SECONDS - ultimo)) -ge 60 ]; then
    ultimo=$SECONDS; echo "(instalando $id, $SECONDS s)" >&2
  fi
  sleep 5
done
echo "la instalación de $id no terminó en $limite s" >&2
exit 124
