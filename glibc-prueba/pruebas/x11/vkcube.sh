#!/usr/bin/bash
# B36: Turnip (con turnip/parches/0004) dibuja en el servidor X de la app por DRI3 con los buffers del servidor: vkcube
# no muere, el WSI no avisa que el servidor no dio sus buffers, la ventana no queda negra y termina sus cuadros.
# Corre DENTRO de la app, con un escritorio X11 abierto y vkcube instalado:
#   scripts/probar-en-telefono.sh <instancia> pruebas/x11/vkcube.sh
# TURNIP_LIB elige el libvulkan_freedreno.so (por defecto el de /usr/local/turnip-x11).
export DISPLAY=${DISPLAY:-:10}
unset WAYLAND_DISPLAY LD_PRELOAD MESA_VK_WSI_DEBUG
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }
LIB=${TURNIP_LIB:-/usr/local/turnip-x11/lib/libvulkan_freedreno.so}
d=$(mktemp -d)
printf '{"file_format_version":"1.0.1","ICD":{"library_path":"%s","api_version":"1.3.0"}}\n' "$LIB" > "$d/icd.json"
export VK_DRIVER_FILES=$d/icd.json

# 1) mientras gira: la ventana titulada vkcube (_NET_WM_NAME "Vkcube X11") (no la activa: puede ser otra) no está negra en el centro y cambia de un
#    segundo al siguiente (el cubo gira: si el servidor mostrara siempre el mismo cuadro, o nada, no cambiaría)
vkcube --wsi xcb > "$d/vk1.log" 2>&1 & pid=$!
sleep 6
ventana=
for w in $(xprop -root _NET_CLIENT_LIST 2>/dev/null | grep -o '0x[0-9a-f]*'); do
  xprop -id "$w" _NET_WM_NAME 2>/dev/null | grep -qi '"vkcube' && { ventana=$w; break; }
done
leer_centro() { python3 - "$ventana" <<'PY'
import ctypes, sys, zlib
xcb = ctypes.CDLL("libxcb.so.1")
xcb.xcb_connect.restype = ctypes.c_void_p
xcb.xcb_connect.argtypes = [ctypes.c_char_p, ctypes.c_void_p]
class Cookie(ctypes.Structure): _fields_ = [("sequence", ctypes.c_uint)]
class Geo(ctypes.Structure):
    _fields_ = [("rt", ctypes.c_uint8), ("depth", ctypes.c_uint8), ("seq", ctypes.c_uint16), ("len", ctypes.c_uint32),
                ("root", ctypes.c_uint32), ("x", ctypes.c_int16), ("y", ctypes.c_int16),
                ("w", ctypes.c_uint16), ("h", ctypes.c_uint16), ("bw", ctypes.c_uint16)]
for f, r in (("xcb_get_geometry", Cookie), ("xcb_get_image", Cookie)): getattr(xcb, f).restype = r
xcb.xcb_get_geometry.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
xcb.xcb_get_geometry_reply.restype = ctypes.POINTER(Geo)
xcb.xcb_get_geometry_reply.argtypes = [ctypes.c_void_p, Cookie, ctypes.c_void_p]
xcb.xcb_get_image.argtypes = [ctypes.c_void_p, ctypes.c_uint8, ctypes.c_uint32, ctypes.c_int16, ctypes.c_int16,
                              ctypes.c_uint16, ctypes.c_uint16, ctypes.c_uint32]
xcb.xcb_get_image_reply.restype = ctypes.c_void_p
xcb.xcb_get_image_reply.argtypes = [ctypes.c_void_p, Cookie, ctypes.c_void_p]
xcb.xcb_get_image_data.restype = ctypes.POINTER(ctypes.c_uint32)
xcb.xcb_get_image_data.argtypes = [ctypes.c_void_p]
c = xcb.xcb_connect(None, None)
w = int(sys.argv[1], 16) if len(sys.argv) > 1 and sys.argv[1] else 0
g = xcb.xcb_get_geometry_reply(c, xcb.xcb_get_geometry(c, w), None)
if not w or not g: print("sin-ventana"); sys.exit()
n = 64
r = xcb.xcb_get_image_reply(c, xcb.xcb_get_image(c, 2, w, g.contents.w // 2 - n // 2, g.contents.h // 2 - n // 2, n, n,
                                                 0xffffffff), None)
if not r: print("sin-imagen"); sys.exit()
px = [xcb.xcb_get_image_data(r)[i] & 0xffffff for i in range(n * n)]
print("%06x %08x" % (max(px), zlib.crc32(bytes(str(px), "ascii"))))
PY
}
uno=$(leer_centro); sleep 1; dos=$(leer_centro)
kill $pid 2>/dev/null; wait $pid 2>/dev/null
echo "      ventana vkcube: ${ventana:-ninguna}; centro (más claro, crc): $uno / $dos"
caso "hay una ventana titulada vkcube"  '[ -n "$ventana" ]'
caso "la ventana de vkcube no está negra en el centro"  '[[ ${uno%% *} =~ ^[0-9a-f]{6}$ ]] && [ "${uno%% *}" != 000000 ]'
caso "el centro cambia de un segundo al siguiente (el cubo gira)"  '[[ $uno =~ ^[0-9a-f]{6}\ [0-9a-f]{8}$ ]] && [ "${uno#* }" != "${dos#* }" ]'

# 2) 300 cuadros y sale con 0, por DRI3 con los buffers del servidor
timeout 60 vkcube --wsi xcb --c 300 > "$d/vk2.log" 2>&1; rc=$?
caso "vkcube --c 300 termina con 0 (salió $rc)"  '[ $rc -eq 0 ]'
caso "el WSI recibió los buffers del servidor (sin aviso de BuffersFromPixmap)"  '! grep -q "no entregó sus buffers" "$d/vk1.log" "$d/vk2.log"'
[ $fallas -eq 0 ] || tail -5 "$d/vk2.log"
rm -rf "$d"
echo "fallas: $fallas"
[ $fallas -eq 0 ]
