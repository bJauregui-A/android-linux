#!/usr/bin/bash
# B36: lo compilado en el teléfono ya no vive en files/archlinux (las instancias reemplazaron a esa raíz):
# apk/traer-compilados.sh --de <instancia> <nombre>... reemplaza solo esos componentes de trabajo/compilados.tar con los
# de files/instancias/<instancia>/home/user/<nombre>, y deja el resto como estaba.
# Corre en el PC con un adb de mentira y un árbol temporal:  pruebas/capa/traer.sh
cd "$(dirname "$0")/../.." || exit 1
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/repo/apk" "$T/repo/trabajo" "$T/bin" "$T/tel/files/instancias/inst-1/home/user/turnip-x11/lib"
cp apk/traer-compilados.sh "$T/repo/apk/"
# compilados.tar viejo: turnip-x11 y sway
mkdir -p "$T/viejo/home/user/turnip-x11/lib" "$T/viejo/home/user/sway/bin"
echo viejo > "$T/viejo/home/user/turnip-x11/lib/libvulkan_freedreno.so"
echo viejo > "$T/viejo/home/user/turnip-x11/lib/sobra.so"
echo sway > "$T/viejo/home/user/sway/bin/sway"
tar -C "$T/viejo" -cf "$T/repo/trabajo/compilados.tar" home/user/turnip-x11 home/user/sway
echo nuevo > "$T/tel/files/instancias/inst-1/home/user/turnip-x11/lib/libvulkan_freedreno.so"
mkdir -p "$T/tel/files/instancias/inst-1/home/user/turnip-x11/include"; echo h > "$T/tel/files/instancias/inst-1/home/user/turnip-x11/include/x.h"
# adb de mentira: como el real, junta los argumentos de exec-out en una línea para la shell del teléfono; "run-as <pkg>"
# corre el resto en la carpeta de la app
cat > "$T/bin/adb" <<'A'
#!/usr/bin/bash
[ "$1" = exec-out ] || exit 1
shift; linea="$*"
[[ $linea == "run-as "* ]] || exit 1
linea=${linea#run-as }; linea=${linea#* }
cd "$TEL" && eval "$linea"
A
chmod +x "$T/bin/adb"
(cd "$T/repo" && TEL=$T/tel PATH="$T/bin:$PATH" apk/traer-compilados.sh sdk36 --de inst-1 turnip-x11 > "$T/salida" 2>&1); rc=$?
lista=$(tar -tf "$T/repo/trabajo/compilados.tar" 2>/dev/null)
caso "sale con 0"  '[ $rc -eq 0 ] || { cat "$T/salida"; false; }'
caso "turnip-x11 es el de la instancia"  '[ "$(tar -xOf "$T/repo/trabajo/compilados.tar" home/user/turnip-x11/lib/libvulkan_freedreno.so)" = nuevo ]'
caso "no quedan archivos viejos de turnip-x11"  '! grep -q "turnip-x11/lib/sobra.so" <<<"$lista"'
caso "sin include/"  '! grep -q "turnip-x11/include" <<<"$lista"'
caso "lo demás (sway) sigue igual"  '[ "$(tar -xOf "$T/repo/trabajo/compilados.tar" home/user/sway/bin/sway)" = sway ]'
# Sin --de, en un teléfono sin files/archlinux: falla, dice que se use --de y no toca el compilados.tar que hay
cp "$T/repo/trabajo/compilados.tar" "$T/antes.tar"
(cd "$T/repo" && TEL=$T/tel PATH="$T/bin:$PATH" apk/traer-compilados.sh sdk36 > "$T/salida" 2>&1); rc=$?
caso "sin --de ni files/archlinux sale con error"  '[ $rc -ne 0 ]'
caso "sin --de ni files/archlinux sugiere --de"  'grep -q -- "--de" "$T/salida" || { cat "$T/salida"; false; }'
caso "sin --de ni files/archlinux compilados.tar sigue igual"  'cmp -s "$T/antes.tar" "$T/repo/trabajo/compilados.tar"'
echo "fallas: $fallas"
[ $fallas -eq 0 ]
