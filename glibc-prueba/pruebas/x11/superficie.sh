#!/usr/bin/bash
# B11: la vista le manda la superficie al servidor varias veces (surfaceChanged, onResume, foco, reajustar) y en el
# proceso :x11 cada envío es un Surface Java nuevo sobre la misma BufferQueue. Si el anterior no se suelta, sigue
# conectado como productor hasta el GC: ANativeWindow_lock del nuevo falla ("connect: already connected") y la
# imagen se queda congelada (B36: la capa ASurfaceControl se crea sobre el Surface, que también hay que soltar). Corre en el PC:  pruebas/x11/superficie.sh
cd "$(dirname "$0")/../.." || exit 1
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }
SRV=app/src/main/java/dev/ben4shot/glibcprueba/ServicioX11.java
DDX=x11/ddx/android/InitOutput.c

caso "ServicioX11 suelta el Surface anterior al recibir otro"  'grep -q "\.release()" $SRV'
# Sin capa no sale nada: el cuadro completo queda pendiente hasta que el setBuffer salga con una capa.
pres=$(sed -n '/^androidPresentar/,/^}/p' $DDX)
bh=$(sed -n '/^androidBlockHandler/,/^}/p' $DDX)
caso "androidPresentar dice si pudo presentar"  'grep -qE "^static Bool$" <<<"$(grep -B1 "^androidPresentar" $DDX)"'
caso "androidPresentar no hace nada sin capa"  'grep -qE "if \(!capa" <<<"$pres" && [ "$(grep -n "if (!capa" <<<"$pres" | head -1 | cut -d: -f1)" -lt "$(grep -n "ASurfaceTransaction_setBuffer" <<<"$pres" | head -1 | cut -d: -f1)" ]'
caso "el block handler no da por presentada una ventana nueva si no salió el setBuffer"  \
  'l_pres=$(grep -n "androidPresentar" <<<"$bh" | head -1 | cut -d: -f1); l_hecha=$(grep -n "ventana_nueva = FALSE" <<<"$bh" | head -1 | cut -d: -f1); [ -n "$l_pres" ] && [ -n "$l_hecha" ] && [ "$l_hecha" -gt "$l_pres" ]'
caso "androidVentana crea la capa con ASurfaceControl_createFromWindow y suelta la anterior"  \
  'v=$(sed -n "/^androidVentana/,/^}/p" $DDX); grep -q ASurfaceControl_createFromWindow <<<"$v" && grep -q ASurfaceControl_release <<<"$v"'

echo "fallas: $fallas"
[ $fallas -eq 0 ]
