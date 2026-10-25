#!/bin/bash
# Pruebas C13-C20 de B26. Correr DENTRO de una instancia (solo lectura).
# Imprime OK/FALLA por línea y un resumen.
fallas=0
chk() { # id descripción valor-obtenido valor-esperado
  if [ "$3" = "$4" ]; then echo "OK    $1 $2"
  else echo "FALLA $1 $2"; echo "      obtenido: $3"; echo "      esperado: $4"; fallas=$((fallas+1)); fi
}
raiz=$(ls /)
cd /
chk C13 "cd / && ls .."            "$(ls ..)"            "$raiz"
chk C14 "ls /.."                   "$(ls /..)"           "$raiz"
chk C14 "ls /../.."                "$(ls /../..)"        "$raiz"

# C15: otra instancia hermana, por su nombre real (se ve por la ruta de /data)
base=$(dirname "$GLIBC_PREFIX"); yo=$(basename "$GLIBC_PREFIX")
otra=$(ls "$base" 2>/dev/null | grep -vx "$yo" | head -1)
if [ -n "$otra" ]; then
  r=$(cat "/../$otra/etc/hostname" 2>&1 >/dev/null | sed 's/.*: //')
  chk C15 "cat /../$otra/etc/hostname" "$r" "No such file or directory"
else echo "SALTA C15 (no hay otra instancia)"; fi

chk C16 "cd -P /.. && pwd"         "$(cd -P /.. && pwd)" "/"
chk C17 "realpath /../.."          "$(realpath /../..)"  "/"
chk C17 "readlink -f /lib/.."      "$(readlink -f /lib/..)" "/usr"
if command -v python3 >/dev/null; then
  chk C18 "os.listdir('/..')" "$(python3 -c "import os; print(sorted(os.listdir('/..')) == sorted(os.listdir('/')))")" "True"
else echo "SALTA C18 (sin python3)"; fi

# C19: binario estático/Go (capa seccomp 0015). Pasar uno con: ESTATICO=/ruta/bin
if [ -n "$ESTATICO" ]; then
  chk C19 "$ESTATICO ls /.." "$($ESTATICO ls /.. 2>&1)" "$raiz"
else echo "SALTA C19 (definir ESTATICO=<binario estático con 'ls'>)"; fi

# C20: carpetas de Android no se encierran. Comparar contra la salida guardada
# con la libc anterior: ./en-telefono.sh guardar   |   ./en-telefono.sh
ref=${TMPDIR:-/tmp}/raiz-c20.ref
act=$(ls /proc/self/.. 2>&1 | head -5; ls /sdcard/.. 2>&1 | head -5)
if [ "$1" = guardar ]; then echo "$act" > "$ref"; echo "C20 referencia guardada en $ref"
elif [ -f "$ref" ]; then chk C20 "/proc/self/.. y /sdcard/.." "$act" "$(cat "$ref")"
else echo "SALTA C20 (sin referencia: correr antes con 'guardar' y la libc actual)"; fi

echo "---"; [ $fallas = 0 ] && echo "TELEFONO: OK" || echo "TELEFONO: $fallas FALLAS"
exit $((fallas != 0))
