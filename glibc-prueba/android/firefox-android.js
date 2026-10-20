// Firefox en Linux dentro de Android (va en /usr/lib/firefox/browser/defaults/preferences/; lo
// copia scripts/subir-android.sh con @P@ = el prefijo). La glibc traduce /usr, /etc, ~... al
// prefijo antes de cada llamada, así que el broker del sandbox de contenido recibe rutas reales
// del prefijo (y las resuelve: /data/user/0 → /data/data). Se permiten las mismas que la política
// normal deja leer: sistema y ~/.config/mozilla.
pref("security.sandbox.content.read_path_whitelist", "/data/user/0/@P@/usr/,/data/user/0/@P@/etc/,/data/user/0/@P@/home/user/.config/mozilla/,/data/data/@P@/usr/,/data/data/@P@/etc/,/data/data/@P@/home/user/.config/mozilla/");

// GPU: no forzar gfx.webrender.all. Zink entra a EGL por el camino swrast (sin nodo DRM), gfxtest
// responde MESA_ACCELERATED FALSE y Firefox elige WebRender Software. Forzado, WebRender corre en
// llvmpipe (su contexto sin superficie no pasa por kopper: ~6 núcleos con un video), y con
// GALLIUM_DRIVER=zink carga Turnip pero las ventanas salen negras. Pendiente.
