#!/usr/bin/bash
# B36: OpenGL por la GPU en X11 directo: con-gpu elige kopper (Zink sobre el WSI X11 de Turnip, que dibuja en los buffers
# del servidor por DRI3) y no drisw (Zink con lectura a la CPU y XPutImage). es2gears dibuja (su ventana cambia), EGL no
# avisa "DRI3 error" y el renderer es Zink sobre Turnip.
# Corre DENTRO de la app, con un escritorio X11 abierto y mesa-utils instalado:
#   scripts/probar-en-telefono.sh <instancia> pruebas/x11/gl.sh
export DISPLAY=${DISPLAY:-:10}
unset WAYLAND_DISPLAY LD_PRELOAD MESA_LOADER_DRIVER_OVERRIDE LIBGL_KOPPER_DRI2 GALLIUM_DRIVER
# probar-en-telefono.sh no hereda el entorno de la sesión; la de X11 directo exporta esta capacidad
export ARCH_ANDROID_PROVIDER_CAPABILITIES=${ARCH_ANDROID_PROVIDER_CAPABILITIES:-x11-directo}
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }
d=$(mktemp -d)

con-gpu stdbuf -oL es2gears_x11 > "$d/gl.log" 2>&1 & pid=$!
sleep 6
ventana=
for w in $(xprop -root _NET_CLIENT_LIST 2>/dev/null | grep -o '0x[0-9a-f]*'); do
  xprop -id "$w" WM_NAME 2>/dev/null | grep -q '"es2gears"' && { ventana=$w; break; }
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
# Pide a xfwm4 pantalla completa (_NET_WM_STATE) y escucha los PresentCompleteNotify de la ventana (cualquier cliente
# puede): imprime el modo de cada cuadro entregado después, "copia", "flip", "salto" o "copia-subóptima".
modos_pantalla_completa() { python3 - "$ventana" <<'PY'
import ctypes, sys, time
xcb = ctypes.CDLL("libxcb.so.1"); pres = ctypes.CDLL("libxcb-present.so.0")
class Cookie(ctypes.Structure): _fields_ = [("sequence", ctypes.c_uint)]
class Atom(ctypes.Structure): _fields_ = [("rt", ctypes.c_uint8), ("pad", ctypes.c_uint8), ("seq", ctypes.c_uint16),
                                           ("len", ctypes.c_uint32), ("atom", ctypes.c_uint32)]
xcb.xcb_connect.restype = ctypes.c_void_p
xcb.xcb_connect.argtypes = [ctypes.c_char_p, ctypes.c_void_p]
xcb.xcb_get_setup.restype = ctypes.c_void_p
xcb.xcb_get_setup.argtypes = [ctypes.c_void_p]
class Iter(ctypes.Structure): _fields_ = [("data", ctypes.POINTER(ctypes.c_uint32)), ("rem", ctypes.c_int),
                                           ("index", ctypes.c_int)]  # data: xcb_screen_t*, root es su primer campo
xcb.xcb_setup_roots_iterator.restype = Iter
xcb.xcb_setup_roots_iterator.argtypes = [ctypes.c_void_p]
xcb.xcb_intern_atom.restype = Cookie
xcb.xcb_intern_atom.argtypes = [ctypes.c_void_p, ctypes.c_uint8, ctypes.c_uint16, ctypes.c_char_p]
xcb.xcb_intern_atom_reply.restype = ctypes.POINTER(Atom)
xcb.xcb_intern_atom_reply.argtypes = [ctypes.c_void_p, Cookie, ctypes.c_void_p]
xcb.xcb_send_event.argtypes = [ctypes.c_void_p, ctypes.c_uint8, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_char_p]
xcb.xcb_generate_id.argtypes = [ctypes.c_void_p]
xcb.xcb_flush.argtypes = [ctypes.c_void_p]
xcb.xcb_poll_for_event.restype = ctypes.POINTER(ctypes.c_uint8 * 32)
xcb.xcb_poll_for_event.argtypes = [ctypes.c_void_p]
pres.xcb_present_select_input.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_uint32]
c = xcb.xcb_connect(None, None)
w = int(sys.argv[1], 16) if len(sys.argv) > 1 and sys.argv[1] else 0
if not w: sys.exit()
root = xcb.xcb_setup_roots_iterator(xcb.xcb_get_setup(c)).data[0]
atomo = lambda n: xcb.xcb_intern_atom_reply(c, xcb.xcb_intern_atom(c, 0, len(n), n), None).contents.atom
estado, completa = atomo(b"_NET_WM_STATE"), atomo(b"_NET_WM_STATE_FULLSCREEN")
ev = (bytes([33, 32, 0, 0]) + w.to_bytes(4, "little") + estado.to_bytes(4, "little") +
      b"".join(v.to_bytes(4, "little") for v in (1, completa, 0, 1, 0)))  # ClientMessage: _NET_WM_STATE_ADD
xcb.xcb_send_event(c, 0, root, (1 << 19) | (1 << 20), ev)                 # SubstructureNotify | SubstructureRedirect
xcb.xcb_flush(c)
time.sleep(1)                                                              # que el gestor la agrande
pres.xcb_present_select_input(c, xcb.xcb_generate_id(c), w, 2)            # PresentCompleteNotifyMask
xcb.xcb_flush(c)
nombres = {0: "copia", 1: "flip", 2: "salto", 3: "copia-subóptima"}
modos, fin = [], time.time() + 3
while time.time() < fin and len(modos) < 60:
    e = xcb.xcb_poll_for_event(c)
    if not e: time.sleep(0.01); continue
    b = bytes(e.contents)
    # GenericEvent de Present: event_type (u16) en 8, kind en 10 (0: pixmap) y mode en 11
    if b[0] & 0x7f == 35 and int.from_bytes(b[8:10], "little") == 1 and b[10] == 0:
        modos.append(nombres.get(b[11], "otro"))
print(" ".join(modos))
PY
}
uno=$(leer_centro); sleep 1; dos=$(leer_centro)
# El compositor de xfwm4 deja redirigida la ventana a pantalla completa y Present copia: se apaga mientras se mide y
# se deja como estaba
compositor=$(xfconf-query -c xfwm4 -p /general/use_compositing 2>/dev/null)
[ "$compositor" = true ] && { trap 'xfconf-query -c xfwm4 -p /general/use_compositing -s true' EXIT
                              xfconf-query -c xfwm4 -p /general/use_compositing -s false; sleep 1; }
modos=$(modos_pantalla_completa)
[ "$compositor" = true ] && { xfconf-query -c xfwm4 -p /general/use_compositing -s true; trap - EXIT; }
sleep 2; kill $pid 2>/dev/null; wait $pid 2>/dev/null
echo "      ventana es2gears: ${ventana:-ninguna}; centro (más claro, crc): $uno / $dos"
grep -m1 "FPS" "$d/gl.log" | sed 's/^/      /'
caso "hay una ventana es2gears"  '[ -n "$ventana" ]'
caso "el centro cambia de un segundo al siguiente (los engranajes giran)"  '[[ $uno =~ ^[0-9a-f]{6}\ [0-9a-f]{8}$ ]] && [ "${uno#* }" != "${dos#* }" ]'
caso "EGL no cae al camino sin DRI3 (sin \"DRI3 error\")"  '! grep -q "DRI3 error" "$d/gl.log"'
echo "      a pantalla completa, modos: $(tr ' ' '\n' <<<"$modos" | sort | uniq -c | tr '\n' ' ')"
caso "a pantalla completa los cuadros de es2gears se entregan por flip"  '[ -n "$modos" ] && [ "${modos##* }" = flip ]'
renderer=$(con-gpu eglinfo -p x11 2>/dev/null | grep -m1 "OpenGL ES profile renderer")
echo "      ${renderer:-sin renderer}"
caso "el renderer es Zink sobre Turnip"  'grep -q "zink.*Turnip" <<<"$renderer"'
rm -rf "$d"
echo "fallas: $fallas"
[ $fallas -eq 0 ]
