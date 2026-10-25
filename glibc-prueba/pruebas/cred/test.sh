#!/bin/bash
# Pruebas de las credenciales virtuales (B27, fase 1) DENTRO de una instancia.
#   pruebas/cred/test.sh <instancia>
# Compila prueba.c con el compilador cruzado (Docker), lo manda dentro del script de
# scripts/probar-en-telefono.sh y corre los casos con el seccomp real de la app.
# Salida 0 si todos dan OK.
set -e
AQUI=$(cd "$(dirname "$0")" && pwd)
inst=${1:?uso: $0 <instancia>}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
docker run --rm -u "$(id -u):$(id -g)" -v "$AQUI:/w" -v "$T:/o" -w /w glibc-cross \
  sh -c "aarch64-linux-gnu-gcc -Wall -Wextra -Os -o /o/prueba prueba.c && aarch64-linux-gnu-strip /o/prueba"
{
  echo 'P=/tmp/prueba-cred; fallas=0'
  echo "base64 -d <<'FIN' | gzip -dc > \$P"
  gzip -9 -c "$T/prueba" | base64 -w76
  echo 'FIN'
  cat <<'REMOTO'
chmod 755 $P
caso() { "$@" || fallas=$((fallas+1)); }
caso $P real
GLIBC_FAKEROOT=1 caso $P fake
GLIBC_FAKEROOT=1 caso $P cred
GLIBC_FAKEROOT=1 caso $P cola
GLIBC_FAKEROOT=1 caso $P exec
GLIBC_FAKEROOT=1 caso $P execenv
caso $P stat
# el wrapper de sudo: quien lo ejecuta (no root) pide GLIBC_FAKEROOT=1 y el hijo es root
n=$(GLIBC_FAKEROOT=1 $P ids | cut -d' ' -f1-2)
[ "$n" = "0 0" ] && echo "OK wrapper" || { echo "FALLA wrapper: '$n'"; fallas=$((fallas+1)); }
rm -f $P
echo "fallas: $fallas"
exit $fallas
REMOTO
} > "$T/dentro.sh"
"$AQUI/../../scripts/probar-en-telefono.sh" "$inst" "$T/dentro.sh" 120
