#!/usr/bin/bash
# B96: la matriz completa de permisos. Recorre tres usuarios (user, otro y root) contra archivos y carpetas de dos dueños (user y root) en los
# modos 600, 640, 644, 755, 1777, 111 y 070: leer, escribir y ejecutar un archivo; listar, entrar, crear y borrar en una carpeta. Compara cada resultado con
# la tabla de Linux (la función esperado, que sale de las reglas de permisos de Linux y se valida contra el kernel real).
# Corre en dos sitios, con el mismo script:
#   - el PC, contra el kernel de Linux (en un espacio de usuarios con varios uid):
#       unshare --map-auto --setuid 0 --setgid 0 -- bash pruebas/permisos/matriz.sh
#   - DENTRO de una instancia (scripts/probar-en-telefono.sh), como el usuario principal; "otro" es www-data (Debian) o http (Arch).
fallas=0; casos=0
if [ -z "$GLIBC_PREFIX" ]; then
  UU=1001; UG=1001; OU=1002; OG=1002
  actor() { local a=$1; shift
    case $a in
      user) setpriv --reuid=$UU --regid=$UG --clear-groups "$@";;
      otro) setpriv --reuid=$OU --regid=$OG --clear-groups "$@";;
      root) "$@";;
    esac; }
  asroot() { "$@"; }
else
  UU=$(id -u); UG=$(id -g)
  OTRO=www-data; id -u $OTRO >/dev/null 2>&1 || OTRO=http
  OU=$(id -u $OTRO); OG=$(id -g $OTRO)
  actor() { local a=$1; shift
    case $a in
      user) "$@";;
      otro) GLIBC_FAKEROOT=1 setpriv --regid=$OG --clear-groups setpriv --reuid=$OU "$@";;
      root) GLIBC_FAKEROOT=1 "$@";;
    esac; }
  asroot() { GLIBC_FAKEROOT=1 "$@"; }
fi
D=$(mktemp -d /tmp/matriz.XXXXXX) || exit 1
asroot chmod 755 $D
cd $D || exit 1
finalizar() { cd /; asroot chmod -R 777 $D 2>/dev/null; asroot rm -rf $D; }
trap finalizar EXIT

# esperado <actor> <dueño> <modo> <operación>: 0 si Linux lo deja hacer, 1 si no
esperado() {
  local a=$1 d=$2 m=$(( 0$3 & 0777 )) op=$4 bits sticky=$(( 0$3 & 01000 ))
  if [ "$a" = "$d" ]; then bits=$(( (m >> 6) & 7 )); else bits=$(( m & 7 )); fi
  if [ "$a" = root ]; then
    case $op in
      ejecutar) [ $(( m & 0111 )) -ne 0 ] && echo 0 || echo 1;;   # root ejecuta si algún x
      *) echo 0;;
    esac
    return
  fi
  case $op in
    leer|listar)    [ $(( bits & 4 )) -ne 0 ] && echo 0 || echo 1;;
    escribir)       [ $(( bits & 2 )) -ne 0 ] && echo 0 || echo 1;;
    ejecutar)       [ $(( bits & 5 )) -eq 5 ] && echo 0 || echo 1;;   # un script pide r y x
    entrar)         [ $(( bits & 1 )) -ne 0 ] && echo 0 || echo 1;;
    crear)          [ $(( bits & 3 )) -eq 3 ] && echo 0 || echo 1;;
    borrar)
      [ $(( bits & 3 )) -eq 3 ] || { echo 1; return; }
      # con sticky solo borra el dueño de la carpeta (lo de adentro es del dueño de la carpeta)
      if [ $sticky -ne 0 ] && [ "$a" != "$d" ]; then echo 1; else echo 0; fi;;
  esac
}
dueno() { if [ "$1" = user ]; then echo "$UU:$UG"; else echo 0:0; fi; }
# comprobar <actor> <dueño> <modo> <operación> <resultado>
comprobar() {
  local esp; esp=$(esperado "$1" "$2" "$3" "$4"); casos=$((casos + 1))
  if [ "$esp" != "$5" ]; then
    echo "FALLA $4 de $1 sobre algo de $2 en modo $3: esperaba $esp, salió $5"; fallas=$((fallas + 1))
  fi
}
hace() { "$@" >/dev/null 2>&1 && echo 0 || echo 1; }

n=0
for d in user root; do
  for m in 600 640 644 755 1777 111 070; do
    n=$((n + 1)); f=f$n; q=d$n
    printf '#!/bin/sh\nexit 0\n' > $f; asroot chown $(dueno $d) $f; asroot chmod $m $f
    asroot mkdir $q; asroot chown $(dueno $d) $q; asroot chmod $m $q
    for a in user otro root; do
      comprobar $a $d $m leer "$(hace actor $a cat $D/$f)"
      comprobar $a $d $m escribir "$(hace actor $a sh -c 'echo x >> "$0"' $D/$f)"
      comprobar $a $d $m ejecutar "$(hace actor $a $D/$f)"
      comprobar $a $d $m listar "$(hace actor $a ls $D/$q)"
      comprobar $a $d $m entrar "$(hace actor $a sh -c 'cd "$0"' $D/$q)"
      comprobar $a $d $m crear "$(hace actor $a touch $D/$q/nuevo)"; asroot rm -f $D/$q/nuevo
      asroot touch $D/$q/v; asroot chown $(dueno $d) $D/$q/v
      comprobar $a $d $m borrar "$(hace actor $a rm $D/$q/v)"; asroot rm -f $D/$q/v
    done
  done
done
echo "casos: $casos"
echo "fallas: $fallas"
exit $fallas
