#!/usr/bin/bash
# B36: el servidor X de la app anuncia DRI3 y Present (por ahí los clientes reciben los dmabuf de AHardwareBuffer que
# reserva el servidor). Corre DENTRO de la app, con un escritorio X11 abierto (DISPLAY :10 por defecto):
#   scripts/probar-en-telefono.sh <instancia> pruebas/x11/dri3.sh
export DISPLAY=${DISPLAY:-:10}
python3 - <<'PY'
import ctypes, sys
xcb = ctypes.CDLL("libxcb.so.1")
xcb.xcb_connect.restype = ctypes.c_void_p
xcb.xcb_connect.argtypes = [ctypes.c_char_p, ctypes.c_void_p]
xcb.xcb_connection_has_error.argtypes = [ctypes.c_void_p]
class Cookie(ctypes.Structure): _fields_ = [("sequence", ctypes.c_uint)]
class Reply(ctypes.Structure):
    _fields_ = [("response_type", ctypes.c_uint8), ("pad0", ctypes.c_uint8), ("sequence", ctypes.c_uint16),
                ("length", ctypes.c_uint32), ("present", ctypes.c_uint8), ("major_opcode", ctypes.c_uint8),
                ("first_event", ctypes.c_uint8), ("first_error", ctypes.c_uint8)]
xcb.xcb_query_extension.restype = Cookie
xcb.xcb_query_extension.argtypes = [ctypes.c_void_p, ctypes.c_uint16, ctypes.c_char_p]
xcb.xcb_query_extension_reply.restype = ctypes.POINTER(Reply)
xcb.xcb_query_extension_reply.argtypes = [ctypes.c_void_p, Cookie, ctypes.c_void_p]
c = xcb.xcb_connect(None, None)
if not c or xcb.xcb_connection_has_error(c):
    print("FALLA no hay conexión con el servidor X"); print("fallas: 1"); sys.exit(1)
fallas = 0
for ext in (b"DRI3", b"Present"):
    r = xcb.xcb_query_extension_reply(c, xcb.xcb_query_extension(c, len(ext), ext), None)
    ok = bool(r) and r.contents.present
    print(("OK    " if ok else "FALLA ") + "el servidor anuncia " + ext.decode())
    fallas += not ok
print("fallas:", fallas)
sys.exit(1 if fallas else 0)
PY
