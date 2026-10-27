#!/usr/bin/bash
# B11: la vista le manda la superficie al servidor varias veces (surfaceChanged, onResume, foco, reajustar) y en el
# proceso :x11 cada envío es un Surface Java nuevo sobre la misma BufferQueue. Si el anterior no se suelta, sigue
# conectado como productor hasta el GC: ANativeWindow_lock del nuevo falla ("connect: already connected") y la
# imagen se queda congelada. Corre en el PC:  pruebas/x11/superficie.sh
cd "$(dirname "$0")/../.." || exit 1
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }
SRV=app/src/main/java/dev/ben4shot/glibcprueba/ServicioX11.java
DDX=x11/ddx/android/InitOutput.c

caso "ServicioX11 suelta el Surface anterior al recibir otro"  'grep -q "\.release()" $SRV'
# Lo que no se pudo copiar no se pierde: el cuadro completo queda pendiente hasta que el lock funcione.
bh=$(sed -n '/^androidBlockHandler/,/^}/p' $DDX)
caso "androidCopiar dice si pudo copiar"  'grep -qE "^static Bool$" <<<"$(grep -B1 "^androidCopiar" $DDX)"'
caso "el block handler no da por copiada una ventana nueva si el lock falla"  \
  'l_copia=$(grep -n "androidCopiar" <<<"$bh" | head -1 | cut -d: -f1); l_hecha=$(grep -n "ventana_nueva = FALSE" <<<"$bh" | head -1 | cut -d: -f1); [ -n "$l_copia" ] && [ -n "$l_hecha" ] && [ "$l_hecha" -gt "$l_copia" ]'

echo "fallas: $fallas"
[ $fallas -eq 0 ]
