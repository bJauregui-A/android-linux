#!/usr/bin/bash
# B36: el servidor X11 dibuja en AHardwareBuffer y los entrega a SurfaceFlinger con ASurfaceTransaction, sin copiar
# fila por fila a un ANativeWindow. Corre en el PC (compila libxserver.so si hace falta):  pruebas/x11/ahb.sh
cd "$(dirname "$0")/../.." || exit 1
export LC_ALL=C
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }
DDX=x11/ddx/android/InitOutput.c
LIB=x11/salida/libxserver.so

x11/compilar.sh xserver >/tmp/x11-ahb-compilar.log 2>&1 || { echo "FALLA x11/compilar.sh xserver terminó con error (ver /tmp/x11-ahb-compilar.log)"; exit 1; }
importa() { nm -D --undefined-only $LIB | grep -qw "$1"; }

for s in ASurfaceTransaction_setBuffer ASurfaceControl_createFromWindow AHardwareBuffer_allocate; do
  caso "libxserver.so importa $s"  "importa $s"
done
for s in ANativeWindow_lock ANativeWindow_unlockAndPost; do
  caso "libxserver.so ya no importa $s"  "! importa $s"
done

vfb=$(sed -n '/^vfbAllocateFramebufferMemory/,/^}/p' $DDX)
res=$(sed -n '/^androidReservarPantalla/,/^}/p' $DDX)
caso "vfbAllocateFramebufferMemory reserva la pantalla con androidReservarPantalla, que usa AHardwareBuffer_allocate"  \
  'grep -q "androidReservarPantalla" <<<"$vfb" && grep -q "AHardwareBuffer_allocate" <<<"$res"'
caso "vfbAllocateFramebufferMemory no usa malloc para el framebuffer de pantalla"  '! grep -q "malloc(pvfb->sizeInBytes)" <<<"$vfb"'
caso "el block handler entrega con androidPresentar"  'sed -n "/^androidBlockHandler/,/^}/p" $DDX | grep -q androidPresentar'
pres=$(sed -n '/^androidPresentar/,/^}/p' $DDX)
caso "androidPresentar cambia el pixmap de pantalla después de entregar el buffer"  \
  'l_set=$(grep -n "ASurfaceTransaction_setBuffer" <<<"$pres" | head -1 | cut -d: -f1); l_mod=$(grep -n "ModifyPixmapHeader" <<<"$pres" | head -1 | cut -d: -f1); [ -n "$l_set" ] && [ -n "$l_mod" ] && [ "$l_mod" -gt "$l_set" ]'

# Al reiniciarse el servidor (se fue el último cliente) vfbScreenInit corre otra vez con los AHB ya reservados: si
# recalcula el stride con PixmapBytePad en vez de usar el de gralloc, fb dibuja con otro ancho y salen rayas.
init=$(sed -n '/^vfbScreenInit/,/^}/p' $DDX)
caso "vfbScreenInit no recalcula el stride si el framebuffer ya existe"  \
  'l_si=$(grep -n "if (!pvfb->pfbMemory)" <<<"$init" | head -1 | cut -d: -f1); l_pad=$(grep -n "paddedBytesWidth = PixmapBytePad" <<<"$init" | head -1 | cut -d: -f1); [ -n "$l_si" ] && [ -n "$l_pad" ] && [ "$l_si" -lt "$l_pad" ]'

# Con dos buffers el que sigue libre es el que se acaba de entregar un cuadro antes y su release fence solo llega en el
# OnComplete de esta transacción: el servidor se bloqueaba un vsync por cuadro (arrastres a tirones, cursor parpadeando).
# Con tres, el libre ya llegó en el OnComplete anterior y se sigue dibujando sin esperar; como queda dos cuadros atrás,
# cada buffer acumula el daño que se perdió (debe[]) y se le copia al tomarlo.
caso "la pantalla usa tres AHardwareBuffer"  'grep -q "AHardwareBuffer \*ahb\[3\]" $DDX'
caso "androidPresentar toma el buffer libre que no es el entregado ni el que se reemplaza"  \
  '! grep -q "1 - actual" <<<"$pres" && grep -q "anterior" <<<"$pres"'
caso "cada buffer acumula el daño que no ha recibido"  \
  'grep -q "RegionUnion" <<<"$pres" && grep -q "debe\[" <<<"$pres"'
caso "el OnComplete deja la release fence en el buffer que reemplazó, no en una sola ranura"  \
  'sed -n "/^androidTransaccionCompleta/,/^}/p" $DDX | grep -q "anterior"'

# Los block handlers registrados (RegisterBlockAndWakeupHandlers) corren antes que pScreen->BlockHandler, donde el
# cursor por software (misprite) se repinta: el cuadro salía sin cursor y el siguiente con él (parpadeo). La entrega
# envuelve pScreen->BlockHandler: misprite se engancha encima, repinta y después llama a la entrega.
init=$(sed -n '/^vfbScreenInit/,/^}/p' $DDX)
caso "la entrega va en pScreen->BlockHandler, puesto después del cursor por software"  \
  'l_dc=$(grep -n "miDCInitialize" <<<"$init" | head -1 | cut -d: -f1); l_bh=$(grep -n "pScreen->BlockHandler = androidBlockHandler" <<<"$init" | head -1 | cut -d: -f1); [ -n "$l_dc" ] && [ -n "$l_bh" ] && [ "$l_bh" -gt "$l_dc" ]'
caso "androidBlockHandler ya no es un block handler registrado"  '! grep -q "RegisterBlockAndWakeupHandlers(androidBlockHandler" $DDX'
bh=$(sed -n '/^androidBlockHandler/,/^}/p' $DDX)
caso "androidBlockHandler llama primero a la cadena envuelta"  \
  'l_env=$(grep -n "(\*pScreen->BlockHandler)" <<<"$bh" | head -1 | cut -d: -f1); l_pres=$(grep -n "androidPresentar" <<<"$bh" | head -1 | cut -d: -f1); [ -n "$l_env" ] && [ -n "$l_pres" ] && [ "$l_env" -lt "$l_pres" ]'

# Al arrastrar, cada vuelta del servidor entregaba una transacción, más de las que SurfaceFlinger toma por vsync: el
# buffer libre aún no se soltaba y el servidor esperaba su fence hasta 100 ms. A lo más una transacción en vuelo: si la
# anterior no terminó, el daño se acumula y el OnComplete despierta al servidor (eventfd + SetNotifyFd).
caso "androidBlockHandler no entrega con una transacción en vuelo"  'grep -q "en_vuelo" <<<"$bh"'
caso "el OnComplete marca el fin de la transacción y despierta al servidor"  \
  'oc=$(sed -n "/^androidTransaccionCompleta/,/^}/p" $DDX); grep -q "en_vuelo" <<<"$oc" && grep -q "write(despertar" <<<"$oc"'
caso "el eventfd que despierta al servidor está en SetNotifyFd"  'grep -q "SetNotifyFd(despertar" $DDX'

echo "fallas: $fallas"
[ $fallas -eq 0 ]
