# Pruebas del setuid/setgid virtual en execve (B27 fase 3). Corre DENTRO de una instancia (probar-en-telefono.sh).
D=/tmp/suid-$$; fallas=0
mkdir -p $D; cd $D
ok() { echo "OK $1"; }
mal() { echo "FALLA $1: $2"; fallas=$((fallas+1)); }
igual() { [ "$2" = "$3" ] && ok "$1" || mal "$1" "esperaba '$3', salió '$2'"; }
R() { GLIBC_FAKEROOT=1 "$@"; }          # como el wrapper de sudo
ME=$(id -u); MG=$(id -g)
ids() { "$@" | tr '\n' ' '; }            # real y efectivo: id -ru; id -u
cp /usr/bin/id sid; chmod 4755 sid; R chown 0:0 sid
igual "sin setuid: efectivo = real" "$(id -u):$(id -ru)" "$ME:$ME"
igual "setuid root: efectivo 0, real intacto" "$(./sid -u):$(./sid -ru)" "0:$ME"
igual "setuid root: gid intacto" "$(./sid -g):$(./sid -rg)" "$MG:$MG"
cp /usr/bin/id sg; chmod 2755 sg; R chown 0:77 sg
igual "setgid: grupo efectivo" "$(./sg -g):$(./sg -rg):$(./sg -u)" "77:$MG:$ME"
cp /usr/bin/id sg0; chmod 2745 sg0; R chown 0:77 sg0
igual "setgid sin x de grupo no cuenta" "$(./sg0 -g)" "$MG"
cp /usr/bin/id sug; chmod 6755 sug; R chown 5:6 sug
igual "setuid+setgid de otro dueño" "$(./sug -u):$(./sug -g)" "5:6"
cp /usr/bin/id mio; chmod 4755 mio
igual "setuid del propio usuario" "$(./mio -u)" "$ME"
printf '#!/bin/sh\nid -u\n' > scr; chmod 4755 scr; R chown 0:0 scr
igual "script setuid se ignora" "$(./scr)" "$ME"
# un proceso root que baja a otro usuario y ejecuta un setuid: el programa gana de nuevo el dueño
igual "root normal ve su ruid" "$(R setpriv --regid=62 --clear-groups sh -c 'id -ru')" "0"
igual "setuid sin ser root entra a root" "$(R setpriv --regid=62 --clear-groups sh -c './sid -u')" "0"
rm -rf $D
echo "fallas: $fallas"; exit $fallas
