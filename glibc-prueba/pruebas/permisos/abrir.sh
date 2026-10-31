#!/bin/bash
# B96: openat2 y O_CREAT|O_EXCL con permisos, DENTRO de una instancia.
#   pruebas/permisos/abrir.sh <instancia>
# Compila abrir.c con el compilador cruzado (Docker), lo manda dentro del script de scripts/probar-en-telefono.sh y
# compara con lo que da Linux. Salida 0 si todos dan OK.
set -e
AQUI=$(cd "$(dirname "$0")" && pwd)
inst=${1:?uso: $0 <instancia>}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
docker run --rm -u "$(id -u):$(id -g)" -v "$AQUI:/w" -v "$T:/o" -w /w glibc-cross \
  sh -c "aarch64-linux-gnu-gcc -Wall -Wextra -Os -o /o/abrir abrir.c && aarch64-linux-gnu-strip /o/abrir"
{
  echo 'P=/tmp/abrir-$$; D=/tmp/abrir-d-$$; fallas=0'
  echo "base64 -d <<'FIN' | gzip -dc > \$P"
  gzip -9 -c "$T/abrir" | base64 -w76
  echo 'FIN'
  cat <<'REMOTO'
chmod 755 $P
ok() { echo "OK $1"; }
mal() { echo "FALLA $1: $2"; fallas=$((fallas+1)); }
igual() { [ "$2" = "$3" ] && ok "$1" || mal "$1" "esperaba '$3', salió '$2'"; }
R() { GLIBC_FAKEROOT=1 "$@"; }
OTRO=www-data; id -u $OTRO >/dev/null 2>&1 || OTRO=http
OU=$(id -u $OTRO); OG=$(id -g $OTRO)
como_otro() { R setpriv --regid=$OG --clear-groups setpriv --reuid=$OU "$@"; }
mkdir -p $D; chmod 755 $D; cd $D
R sh -c 'echo dato > r600; chmod 600 r600'
echo dato > u600; chmod 600 u600; echo dato > u644; chmod 644 u644
for v in openat; do
  igual "$v: user no lee un 600 de root" "$($P $v r600 rd)" "Permission denied"
  igual "$v: otro no lee un 600 de user" "$(como_otro $P $v u600 rd)" "Permission denied"
  igual "$v: otro no escribe un 644 de user" "$(como_otro $P $v u644 wr)" "Permission denied"
  igual "$v: otro lee un 644 de user" "$(como_otro $P $v u644 rd)" "ok"
  igual "$v: user lee y escribe su 600" "$($P $v u600 rdwr)" "ok"
  igual "$v: root lee un 600 de user" "$(R $P $v u600 rd)" "ok"
done
# abrir una carpeta para escribir da EISDIR antes de mirar los permisos (xfdesktop lo hace con /)
igual "dir: user escribe la raíz (de root): EISDIR" "$($P openat / wr)" "Is a directory"
igual "dir: user lee y escribe la raíz: EISDIR" "$($P openat / rdwr)" "Is a directory"
igual "dir: otro escribe la raíz: EISDIR" "$(como_otro $P openat / wr)" "Is a directory"
igual "dir: user lee la raíz: ok" "$($P openat / rd)" "ok"
# openat2 lo bloquea el seccomp de la app (ENOSYS) y glibc cae a openat. Si algún día pasa, hay que comprobar permisos ahí también.
igual "openat2 no está disponible" "$($P openat2 u644 rd)" "Function not implemented"
# O_CREAT|O_EXCL sobre algo que existe: Linux da EEXIST antes de mirar los permisos
igual "excl: user sobre un 600 de root" "$($P openat r600 rd excl)" "File exists"
igual "excl: otro sobre un 600 de user" "$(como_otro $P openat u600 rd excl)" "File exists"
cd /; R rm -rf $D $P
echo "fallas: $fallas"
exit $fallas
REMOTO
} > "$T/dentro.sh"
"$AQUI/../../scripts/probar-en-telefono.sh" "$inst" "$T/dentro.sh" 120
