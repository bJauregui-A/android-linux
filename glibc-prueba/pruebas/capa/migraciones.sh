#!/usr/bin/bash
# B23: cambios de la base que la capa sola no hace (paquetes, configs del sistema) van en apk/migraciones/NNN-<qué>.sh.
# Cada instancia corre una vez, en orden, las que no tiene ($E/migracion guarda la última). Si una falla se detiene ahí
# y la siguiente apertura reintenta desde esa. Una instancia nueva nace con la más alta anotada.
# Corre en el PC (el cargador de la instancia es uno de mentira):  pruebas/capa/migraciones.sh
cd "$(dirname "$0")/../.." || exit 1
eval "$(sed -n '/^numero_migracion() {/,/^}/p; /^migraciones_pendientes() {/,/^}/p; /^migrar() {/,/^}/p; /^anotar_migraciones() {/,/^}/p; /^entorno_app() {/,/^}/p' apk/instalar.sh)"
for f in migraciones_pendientes migrar anotar_migraciones entorno_app; do
    type $f >/dev/null 2>&1 || { echo "FALLA no se encontró $f en apk/instalar.sh"; exit 1; }
done
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
M=usr/local/share/linux-android/migraciones

# instancia <dir> <migraciones...>: cada migración anota su nombre en corridas; "NNN-falla" sale con error
instancia() {
    local r=$1; shift
    mkdir -p "$r/$M" "$r/var/lib/linux-android" "$r/usr/bin"
    for m in "$@"; do
        case $m in
            *falla*) printf 'echo %s >> /corridas; exit 1\n' "$m" > "$r/$M/$m.sh" ;;
            *) printf 'echo %s >> /corridas\n' "$m" > "$r/$M/$m.sh" ;;
        esac
    done
    echo '#!/usr/bin/bash' > "$r/usr/bin/bash"
}
# cargador de mentira: <cargador> /usr/bin/bash /ruta → bash $GLIBC_PREFIX/ruta, con / de la instancia en las rutas
printf '#!/usr/bin/bash\nsed "s#/corridas#$GLIBC_PREFIX/corridas#" "$GLIBC_PREFIX$2" | bash\n' > "$T/cargador"; chmod +x "$T/cargador"
GLIBC_LOADER=$T/cargador
# como dentro de instalar.sh: PATH con /system/bin primero y TMPDIR de Android; el de la app quedó guardado
_PATH_APP=$PATH _TMPDIR_APP= _TMPDIR_HAY= _UMASK_APP=$(umask)
correr() { P=$1 E=$1/var/lib/linux-android GLIBC_PREFIX=$1 PATH=/system/bin:$PATH TMPDIR=/data/x/tmp migrar > "$1.salida" 2>&1; }

R=$T/r1; instancia "$R" 001-a 002-b 010-c
caso "pendientes después de 001: 002 y 010, en orden"  \
  '[ "$(migraciones_pendientes "$R/$M" 001 | xargs -n1 basename | tr "\n" " ")" = "002-b.sh 010-c.sh " ]'
caso "sin última anotada: todas"  \
  '[ "$(migraciones_pendientes "$R/$M" "" | xargs -n1 basename | tr "\n" " ")" = "001-a.sh 002-b.sh 010-c.sh " ]'

R=$T/r2; instancia "$R" 001-a 002-falla 003-c
correr "$R"; rc=$?
caso "migrar con 002 que falla: sale con error"  '[ $rc -ne 0 ]'
caso "migrar con 002 que falla: corre 001 y 002, no 003"  '[ "$(tr "\n" " " < "$R/corridas")" = "001-a 002-falla " ]'
caso "migrar con 002 que falla: anota 001"  '[ "$(cat "$R/var/lib/linux-android/migracion")" = 001 ]'

R=$T/r3; instancia "$R" 001-a 002-b
correr "$R"; rc1=$?; correr "$R"; rc2=$?
caso "migrar dos veces: la segunda no corre ninguna"  '[ $rc1 -eq 0 ] && [ $rc2 -eq 0 ] && [ "$(tr "\n" " " < "$R/corridas")" = "001-a 002-b " ]'
caso "migrar: anota la última"  '[ "$(cat "$R/var/lib/linux-android/migracion")" = 002 ]'

R=$T/r5; instancia "$R" 001-a
echo 'echo "$PATH|${TMPDIR-sin}" > /corridas' > "$R/$M/001-a.sh"
correr "$R"
caso "la migración corre con el PATH y el TMPDIR de la app"  '[ "$(cat "$R/corridas")" = "$_PATH_APP|sin" ]'

R=$T/r4; instancia "$R" 001-a 007-b
P=$R E=$R/var/lib/linux-android anotar_migraciones
caso "instalación nueva: anota la más alta"  '[ "$(cat "$R/var/lib/linux-android/migracion")" = 007 ]'
caso "instalación nueva: no corre ninguna"  '[ ! -e "$R/corridas" ]'

echo "fallas: $fallas"
[ $fallas -eq 0 ]
