#!/bin/bash
# Autoprueba de B29 (casos A1-A9). Se corre desde el PC con una sesión abierta
# en el teléfono. Usa scripts/probar-en-telefono.sh; no escribe en el teléfono
# nada fuera de lo que hace esa herramienta.
#   INSTANCIA=dev-6918 [DEBIAN=<id de una instancia Debian>] ./autoprueba.sh
AQUI=$(cd "$(dirname "$0")" && pwd)
PROBAR=$AQUI/../../scripts/probar-en-telefono.sh
INSTANCIA=${INSTANCIA:-dev-6918}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fallas=0

[ -x "$PROBAR" ] || { echo "FALLA: no existe $PROBAR (todavía)"; echo "AUTOPRUEBA: ROJO"; exit 1; }

# caso <id> <script> <código esperado> <texto esperado en la salida|-> [instancia] [limite]
caso() {
  local id=$1 cuerpo=$2 cod=$3 texto=$4 inst=${5:-$INSTANCIA} lim=${6:-}
  printf '%s\n' "$cuerpo" > "$T/$id.sh"
  local sal rc
  sal=$("$PROBAR" "$inst" "$T/$id.sh" $lim 2>&1); rc=$?
  if [ "$rc" = "$cod" ] && { [ "$texto" = - ] || grep -qF -- "$texto" <<<"$sal"; }; then
    echo "OK    $id"
  else
    echo "FALLA $id (código $rc, esperado $cod; texto '$texto')"; sed 's/^/      /' <<<"$sal" | head -8
    fallas=$((fallas+1))
  fi
}

foco() { adb shell dumpsys window 2>/dev/null | grep mCurrentFocus; }
antes=$(foco)

caso A1 'echo hola' 0 hola
caso A2 'exit 7' 7 -

printf '%s\n' 'echo a; echo b >&2; echo c' > "$T/A3.sh"
orden=$("$PROBAR" "$INSTANCIA" "$T/A3.sh" 2>&1 | tr '\n' ' ')
[ "$orden" = "a b c " ] && echo "OK    A3" || { echo "FALLA A3 (salida: '$orden')"; fallas=$((fallas+1)); }

caso A4 'cat /proc/self/attr/current; grep Seccomp: /proc/self/status' 0 'Seccomp:	2'
caso A5 'cat /etc/os-release; echo $GLIBC_PREFIX' 0 "$INSTANCIA"
[ -n "$DEBIAN" ] && caso A5d 'cat /etc/os-release' 0 Debian "$DEBIAN"

t0=$SECONDS
caso A6 'sleep 30' 124 - "$INSTANCIA" 5
dt=$((SECONDS - t0))
[ "$dt" -le 12 ] && echo "OK    A6 tiempo (${dt}s)" || { echo "FALLA A6: tardó ${dt}s"; fallas=$((fallas+1)); }
vivos=$(adb shell ps -A -o ARGS 2>/dev/null | grep -c 'sleep 30')
[ "$vivos" = 0 ] && echo "OK    A6 sin proceso" || { echo "FALLA A6: quedan $vivos procesos 'sleep 30'"; fallas=$((fallas+1)); }

caso A7 'echo no' 2 'error: instancia' no-existe

printf '%s\n' 'sleep 3; echo uno' > "$T/A8a.sh"; printf '%s\n' 'sleep 3; echo dos' > "$T/A8b.sh"
"$PROBAR" "$INSTANCIA" "$T/A8a.sh" > "$T/A8a.out" 2>&1 & pa=$!
"$PROBAR" "$INSTANCIA" "$T/A8b.sh" > "$T/A8b.out" 2>&1 & pb=$!
wait $pa; ra=$?; wait $pb; rb=$?
if [ $ra = 0 ] && [ $rb = 0 ] && grep -qx uno "$T/A8a.out" && grep -qx dos "$T/A8b.out"; then echo "OK    A8"
else echo "FALLA A8 (códigos $ra $rb)"; fallas=$((fallas+1)); fi

cat > "$T/A9.sh" <<'PY'
python3 - <<'X'
import ctypes, os
libc = ctypes.CDLL(None, use_errno=True)
r = libc.syscall(437, -100, b"/", ctypes.c_void_p(0), 0)   # openat2
print(os.strerror(ctypes.get_errno()))
X
PY
caso A9 "$(cat "$T/A9.sh")" 0 'Function not implemented'

despues=$(foco)
[ "$antes" = "$despues" ] && echo "OK    C1 el foco no cambió" || { echo "FALLA C1: foco '$antes' -> '$despues'"; fallas=$((fallas+1)); }

echo "---"; [ $fallas = 0 ] && echo "AUTOPRUEBA: VERDE" || echo "AUTOPRUEBA: $fallas FALLAS"
exit $((fallas != 0))
