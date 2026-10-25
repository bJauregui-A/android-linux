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

# C15: otra instancia hermana, por su nombre real (se ve por la ruta de /data).
# Se elige un archivo que SÍ exista en ella, para que el fallo no sea casual.
base=$(dirname "$GLIBC_PREFIX"); yo=$(basename "$GLIBC_PREFIX")
otra=; arch=
for d in $(ls "$base" 2>/dev/null | grep -vx -- "$yo"); do
  for f in etc/os-release etc/passwd; do
    [ -f "$base/$d/$f" ] && { otra=$d; arch=$f; break 2; }
  done
done
if [ -n "$otra" ]; then
  r=$(cat "/../$otra/$arch" 2>&1 >/dev/null | sed 's/.*: //')
  chk C15 "cat /../$otra/$arch (existe en $otra)" "$r" "No such file or directory"
else echo "SALTA C15 (no hay otra instancia con etc/os-release)"; fi

chk C16 "cd -P /.. && pwd"         "$(cd -P /.. && pwd)" "/"
chk C17 "realpath /../.."          "$(realpath /../..)"  "/"
# /lib es enlace a usr/lib en Arch (=> /usr) y directorio real en esta Debian (=> /)
chk C17 "readlink -f /lib/.."      "$(readlink -f /lib/..)" "$([ -L /lib ] && echo /usr || echo /)"
if command -v python3 >/dev/null; then
  chk C18 "os.listdir('/..')" "$(python3 -c "import os; print(sorted(os.listdir('/..')) == sorted(os.listdir('/')))")" "True"
else echo "SALTA C18 (sin python3)"; fi

# C19: binario estático (fuera de la glibc de la instancia: capa seccomp 0015).
# Se compila con ./compilar-estatico.sh y se deja en /tmp/rz-estatico.
ES=${ESTATICO:-/tmp/rz-estatico}
if [ -x "$ES" ]; then
  chk C19 "estático: ls /.."        "$("$ES" ls /..)"       "$(LC_ALL=C ls /)"
  chk C19 "estático: ls /../.."     "$("$ES" ls /../..)"    "$(LC_ALL=C ls /)"
  chk C21 "estático: execveat(/, ../usr/bin/echo)" \
      "$("$ES" execveat / ../usr/bin/echo c21e-ok 2>&1)" "c21e-ok"
else echo "SALTA C19 (falta $ES; ver compilar-estatico.sh)"; fi

# C21: execveat con dirfd y '..' por la glibc (hoy armaría /proc/self/fd/N/../..).
if command -v python3 >/dev/null; then
  r=$(python3 - <<'PY' 2>&1
import ctypes, os
fd = os.open('/', os.O_PATH | os.O_DIRECTORY)
libc = ctypes.CDLL(None, use_errno=True)
n = len(os.environ)
envp = (ctypes.c_char_p * (n + 1))(*[f'{k}={v}'.encode() for k, v in os.environ.items()], None)
argv = (ctypes.c_char_p * 3)(b'echo', b'c21-ok', None)
libc.syscall(281, fd, b'../usr/bin/echo', argv, envp, 0)   # execveat
print('execveat fallo: ' + os.strerror(ctypes.get_errno()))
PY
)
  chk C21 "execveat(dirfd=/, ../usr/bin/echo)" "$r" "c21-ok"
else echo "SALTA C21 (sin python3)"; fi

# C20: carpetas de Android no se encierran.
# /proc/self/.. debe salir a /proc (con "self" y "cpuinfo"), no a la raíz de la instancia.
chk C20 "/proc/self/.. sale a /proc" "$(ls /proc/self/.. | grep -cx -e self -e cpuinfo)" "2"
# /sdcard/..: lo que da depende del contexto; se compara con la libc anterior en
# el mismo contexto (lo hace pruebas/raiz/rz.sh, que corre ambas).
echo "SALTA C20b /sdcard/.. (se compara en rz.sh, vieja vs nueva)"

echo "---"; [ $fallas = 0 ] && echo "TELEFONO: OK" || echo "TELEFONO: $fallas FALLAS"
exit $((fallas != 0))
