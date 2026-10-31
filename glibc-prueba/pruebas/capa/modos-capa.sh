#!/usr/bin/bash
# B96: lo compilado en el teléfono entra a la capa con modos de Linux (legible por todos, ejecutable si el dueño lo puede ejecutar), no con
# los 700/600 con que salió de un proceso con umask 077. Corre en el PC:  pruebas/capa/modos-capa.sh
cd "$(dirname "$0")/../.." || exit 1
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/c/home/user/x/lib"
cd "$T/c/home/user/x/lib" || exit 1
for m in 700 600 755 644 500 400 750 640; do echo dato > "f$m"; chmod $m "f$m"; done
cd "$OLDPWD" || exit 1
tar -C "$T/c" -cf "$T/compilados.tar" home
python3 apk/capa.py --prefix /data/user/0/dev.x/files/archlinux --compilados "$T/compilados.tar" --out "$T/capa.tar" >/dev/null 2>"$T/err" \
  || { echo "FALLA capa.py: $(tail -n 3 "$T/err")"; exit 1; }
modo() { tar -tvf "$T/capa.tar" usr/local/x/lib/f$1 | cut -c1-10; }
caso "700 sale rwxr-xr-x"  '[ "$(modo 700)" = "-rwxr-xr-x" ]'
caso "600 sale rw-r--r--"  '[ "$(modo 600)" = "-rw-r--r--" ]'
caso "755 queda igual"     '[ "$(modo 755)" = "-rwxr-xr-x" ]'
caso "644 queda igual"     '[ "$(modo 644)" = "-rw-r--r--" ]'
caso "500 sale r-xr-xr-x"  '[ "$(modo 500)" = "-r-xr-xr-x" ]'
caso "400 sale r--r--r--"  '[ "$(modo 400)" = "-r--r--r--" ]'
caso "750 sale rwxr-xr-x"  '[ "$(modo 750)" = "-rwxr-xr-x" ]'
caso "640 sale rw-r--r--"  '[ "$(modo 640)" = "-rw-r--r--" ]'
echo "fallas: $fallas"
exit $fallas
