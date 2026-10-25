#!/bin/bash
# B29: corre un script de prueba DENTRO de la app (mismo seccomp, misma glibc) en una
# instancia, desde el PC por adb. Imprime la salida y sale con el código del script.
#   probar-en-telefono.sh [--conservar] [--abrir] <instancia> <script-local> [limite-seg]
# Códigos: los del script; 124 por límite de tiempo; 2 error de pedido; 3 no llegó al app.
# Requiere una APK de depuración con ReceptorPruebas. Solo escribe en la carpeta de la app:
# <instancia>/tmp/prueba-<id>.sh y files/pruebas/<id>/ (se borran al terminar).
APP=${APP:-dev.ben4shot.glibcprueba.sdk36}
conservar=0; abrir=0
while [[ $1 == --* ]]; do
  case $1 in --conservar) conservar=1;; --abrir) abrir=1;; *) echo "opción desconocida: $1" >&2; exit 2;; esac
  shift
done
inst=$1; local_sh=$2; limite=${3:-300}
[ -n "$inst" ] && [ -f "$local_sh" ] || { echo "uso: $0 [--conservar] [--abrir] <instancia> <script> [limite]" >&2; exit 2; }
[[ $limite =~ ^[0-9]+$ ]] || { echo "limite debe ser un número de segundos" >&2; exit 2; }
adb get-state >/dev/null 2>&1 || { echo "adb: no hay teléfono conectado" >&2; exit 3; }

id="p-$(date +%s)-$$"
remoto=/tmp/prueba-$id.sh
ra() { adb shell run-as "$APP" "$@" 2>/dev/null; }   # corre como la app (lee/escribe su carpeta)
limpiar() {
  [ $conservar = 1 ] && { echo "(conservado: files/pruebas/$id y $inst$remoto)" >&2; return; }
  ra rm -rf "files/pruebas/$id" "files/instancias/$inst$remoto"
}
trap limpiar EXIT

# 1. subir el script (base64, sin depender de que la instancia tenga nada corriendo).
#    Si la instancia no existe falla en silencio: el app lo dice con "error: instancia".
b64=$(base64 -w0 "$local_sh")
adb shell "run-as $APP sh -c 'echo $b64 | base64 -d > files/instancias/$inst$remoto && chmod 644 files/instancias/$inst$remoto'" >/dev/null 2>&1

# 2. disparar (solo adb tiene DUMP)
disparar() {
  adb shell am broadcast -n "$APP/dev.ben4shot.glibcprueba.ReceptorPruebas" \
    -a dev.ben4shot.glibcprueba.PRUEBA --es instancia "$inst" --es script "$remoto" \
    --es id "$id" --ei limite "$limite" 2>&1
}
r=$(disparar)
if ! grep -q "Broadcast completed" <<<"$r" || grep -qi "error\|exception\|not found" <<<"$r"; then
  echo "el broadcast no llegó al app: ¿APK de depuración con ReceptorPruebas instalada?" >&2
  echo "$r" | head -3 >&2; exit 3
fi

# 3. esperar el código (se escribe al final); tope = limite + 15 s
# Si en 15 s el app no escribió ni "estado", el broadcast no encontró receptor.
fin=$((SECONDS + limite + 15)); arranque=$((SECONDS + 15)); visto=0
while [ $SECONDS -lt $fin ]; do
  est=$(ra cat "files/pruebas/$id/estado")
  [ -n "$est" ] && visto=1
  cod=$(ra cat "files/pruebas/$id/codigo")
  [ -n "$cod" ] && break
  if [ $visto = 0 ] && [ $SECONDS -ge $arranque ] && [ $abrir = 0 ]; then break; fi
  if [ $visto = 0 ] && [ $SECONDS -ge $arranque ] && [ $abrir = 1 ]; then
    echo "(sin servicio: abriendo la app con --abrir; cambia lo que ves en pantalla)" >&2
    adb shell monkey -p "$APP" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1; abrir=0
    r=$(disparar); arranque=$((SECONDS + 15))
  fi
  sleep 1
done
if [ -z "$cod" ]; then
  if [ $visto = 0 ]; then echo "sin respuesta del app (¿servicio en segundo plano?). Probar con --abrir." >&2
  else echo "la prueba no terminó en $((limite + 15)) s" >&2; fi
  exit 3
fi

# 4. mostrar salida y devolver el código
ra cat "files/pruebas/$id/salida.log"
est=$(ra cat "files/pruebas/$id/estado")
case $est in error*) echo "$est";; esac
exit "${cod//[^0-9]/}"
