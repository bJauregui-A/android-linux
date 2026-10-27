#!/usr/bin/bash
# B11: sin ventana (la vista se fue) el servidor no debe hacer dibujar a nadie. Dos piezas:
#  - Present: los avisos del vsync falso (present_fake.c) se retienen y salen al volver la ventana: así xfwm4 con
#    compositor (y GTK, que espera _NET_WM_FRAME_DRAWN) y lo que use Present dejan de dibujar, como con los frame
#    callbacks de Wayland.
#  - Sin compositor (Openbox): una ventana del servidor tapa la pantalla; el dibujo de las demás se recorta a nada y
#    reciben VisibilityNotify. No se copia a Android.
# La medición real es pruebas/x11/fondo.sh en el teléfono. Corre en el PC:  pruebas/x11/pausa.sh
cd "$(dirname "$0")/../.." || exit 1
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }
PAR=x11/parches/xorg-server-21.1.13-android.patch
DDX=x11/ddx/android/InitOutput.c

caso "el parche toca present/present_fake.c"  'grep -q "^+++ b/present/present_fake.c" $PAR'
caso "el parche declara present_fake_pausar en present_priv.h"  \
  'sed -n "/^+++ b\/present\/present_priv.h/,/^diff /p" $PAR | grep -q "^+present_fake_pausar"'
fake=$(sed -n '/^+++ b\/present\/present_fake.c/,/^diff /p' $PAR)
caso "en pausa, un vblank nuevo se retiene en vez de avisar"  'grep -q "^+    if (fake_pausado)" <<<"$fake"'
caso "al reanudar se avisan los retenidos"  'grep -q "^+present_fake_pausar(Bool" <<<"$fake" && grep -q "present_fake_notify" <<<"$fake"'

av=$(sed -n '/^androidVentana(/,/^}/p' $DDX)
caso "androidVentana pausa Present al irse la ventana y lo reanuda al volver"  'grep -q "present_fake_pausar(nueva == NULL)" <<<"$av"'
caso "androidVentana tapa la pantalla al irse y la destapa al volver"  'grep -q "androidTapar(nueva == NULL)" <<<"$av"'
caso "la tapa es override-redirect y del servidor"  'sed -n "/^androidTapar(/,/^}/p" $DDX | grep -q "CWOverrideRedirect" && sed -n "/^androidTapar(/,/^}/p" $DDX | grep -q serverClient'

echo "fallas: $fallas"
[ $fallas -eq 0 ]
