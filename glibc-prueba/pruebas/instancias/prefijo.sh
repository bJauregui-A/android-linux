#!/usr/bin/bash
# primer-arranque.sh ajusta las rutas del prefijo en ld.so.conf.d y en las preferencias de Firefox con
# reescribir_prefijo. La expresión suponía un solo nivel (files/<id>): con files/instancias/<id> reemplazaba solo
# "files/instancias" y la ruta quedaba con el id repetido (files/instancias/<id>/<id>).
# Corre en el PC:  pruebas/instancias/prefijo.sh
cd "$(dirname "$0")/../.." || exit 1
eval "$(sed -n '/^reescribir_prefijo() {/,/^}/p' apk/primer-arranque.sh)"
type reescribir_prefijo >/dev/null 2>&1 || { echo "FALLA no se encontró reescribir_prefijo en apk/primer-arranque.sh"; exit 1; }
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }
APP=dev.ben4shot.glibcprueba.sdk36

P=$APP/files/archlinux
caso "formato viejo (files/<id>): queda igual"  \
  '[ "$(echo /data/user/0/$P/usr/lib | reescribir_prefijo $P)" = "/data/user/0/$P/usr/lib" ]'

P=$APP/files/instancias/arch-1
caso "files/instancias/<id>: el id no se repite"  \
  '[ "$(echo /data/user/0/$P/usr/lib | reescribir_prefijo $P)" = "/data/user/0/$P/usr/lib" ]'
caso "del formato viejo al nuevo: se reemplaza entera"  \
  '[ "$(echo /data/user/0/$APP/files/archlinux/usr/lib | reescribir_prefijo $P)" = "/data/user/0/$P/usr/lib" ]'
caso "de otra instancia a esta: se reemplaza entera"  \
  '[ "$(echo /data/user/0/$APP/files/instancias/vieja-9/usr/lib | reescribir_prefijo $P)" = "/data/user/0/$P/usr/lib" ]'
caso "el marcador @P@ se reemplaza"  \
  '[ "$(echo /data/user/0/@P@/usr/lib | reescribir_prefijo $P)" = "/data/user/0/$P/usr/lib" ]'
caso "una comilla corta la ruta (Firefox)"  \
  '[ "$(echo "\"/data/data/$APP/files/instancias/vieja-9\",x" | reescribir_prefijo $P)" = "\"/data/data/$P\",x" ]'

echo "fallas: $fallas"
[ $fallas -eq 0 ]
