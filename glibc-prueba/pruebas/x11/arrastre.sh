#!/usr/bin/bash
# B36: mientras se arrastra una ventana o se mueve el cursor en un escritorio X11, el servidor no espera a que
# SurfaceFlinger suelte un buffer (antes: hasta 100 ms por cuadro, arrastres pegados). Solo lectura, por adb:
# lee el logcat de los últimos SEG segundos mientras el usuario arrastra.
#   pruebas/x11/arrastre.sh [segundos]      (el usuario arrastra una ventana durante ese tiempo)
SEG=${1:-15}
desde=$(adb shell date +%m-%d\ %H:%M:%S.000)
echo "arrastra una ventana y mueve el cursor durante $SEG s..."
sleep "$SEG"
esperas=$(adb logcat -d -T "$desde" -s x11:W 2>/dev/null | grep -c "esperó")
if [ "$esperas" -eq 0 ]; then echo "OK    el servidor no esperó ninguna liberación de buffer en $SEG s"; exit 0; fi
echo "FALLA el servidor esperó $esperas veces la liberación de un buffer:"
adb logcat -d -T "$desde" -s x11:W | grep "esperó" | tail -5
exit 1
