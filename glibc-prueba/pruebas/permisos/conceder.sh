# Lo que Linux permite por grupo u otros y el kernel niega, porque solo mira los bits del dueño (B96, paso 3). Corre DENTRO de una
# instancia (probar-en-telefono.sh), como el usuario principal. "otro" es www-data (Debian) o http (Arch); root es GLIBC_FAKEROOT=1.
D=/tmp/conceder-$$; fallas=0
ok() { echo "OK $1"; }
mal() { echo "FALLA $1: $2"; fallas=$((fallas+1)); }
igual() { [ "$2" = "$3" ] && ok "$1" || mal "$1" "esperaba '$3', salió '$2'"; }
R() { GLIBC_FAKEROOT=1 "$@"; }
YO=$(id -u); MIG=$(id -g)
OTRO=www-data; id -u $OTRO >/dev/null 2>&1 || OTRO=http
OU=$(id -u $OTRO); OG=$(id -g $OTRO)
como_otro() { R setpriv --regid=$OG --clear-groups setpriv --reuid=$OU "$@"; }
# el mismo "otro" con el grupo del usuario principal como grupo extra (lo que haría usermod -aG)
como_otro_en_grupo() { R setpriv --regid=$OG --groups=$MIG setpriv --reuid=$OU "$@"; }
mkdir -p $D; chmod 755 $D; cd $D
modo() { stat -c %a "$1"; }
# intenta <comando...>: 0 si funciona, 1 si no (sin ruido)
intenta() { "$@" >/dev/null 2>&1 && echo 0 || echo 1; }
# archivo <nombre> <dueño:grupo> <modo> (creado por root)
archivo() { R sh -c "echo dato > $1; chown $2 $1; chmod $3 $1"; }

archivo r044 0:0 044
igual "12. user lee un 044 de root (otros)" "$(intenta cat r044)" "0"
archivo r040 0:$MIG 040
igual "12. user lee un 040 de root:user (grupo)" "$(intenta cat r040)" "0"
archivo r400 0:0 400
igual "12. user no lee un 400 de root" "$(intenta cat r400)" "1"
igual "15. el 044 queda 44" "$(modo r044)" "44"
igual "15. el 040 queda 40" "$(modo r040)" "40"
igual "15. el 400 queda 400" "$(modo r400)" "400"

archivo g040 0:$MIG 040
igual "13. con el grupo extra lee un 040 de ese grupo" "$(intenta como_otro_en_grupo cat g040)" "0"
igual "13. sin el grupo no lo lee" "$(intenta como_otro cat g040)" "1"
igual "15. el 040 queda 40" "$(modo g040)" "40"

echo dato > u666; chmod 666 u666
igual "14. otro escribe un 666 de user" "$(intenta como_otro sh -c 'echo x >> u666')" "0"
echo dato > u006; chmod 006 u006
igual "14. otro escribe un 006 de user (otros)" "$(intenta como_otro sh -c 'echo x >> u006')" "0"
echo dato > u060; chmod 060 u060
igual "14. otro no escribe un 060 de user (solo grupo)" "$(intenta como_otro sh -c 'echo x >> u060')" "1"
igual "15. el 666 queda 666" "$(modo u666)" "666"
igual "15. el 006 queda 6" "$(modo u006)" "6"
igual "15. el 060 queda 60" "$(modo u060)" "60"

# faccessat: test -r/-w dan lo que da open
igual "faccessat: user test -r un 044 de root" "$(intenta /usr/bin/test -r r044)" "0"
igual "faccessat: user test -w un 044 de root" "$(intenta /usr/bin/test -w r044)" "1"
igual "faccessat: otro test -w un 006 de user" "$(intenta como_otro /usr/bin/test -w u006)" "0"
igual "faccessat: no cambia el modo del 044" "$(modo r044)" "44"

# truncate (la syscall, no open): otro trunca un 006 de user
echo dato > t006; chmod 006 t006
como_otro truncate -s 0 t006 2>/dev/null
igual "truncate: otro trunca un 006 de user" "$(stat -c %s t006)" "0"
igual "15. el 006 truncado queda 6" "$(modo t006)" "6"
archivo t644 0:0 644
intenta truncate -s 0 t644 >/dev/null; igual "truncate: user no trunca un 644 de root" "$(stat -c %s t644)" "5"

cd /; R rm -rf $D
echo "fallas: $fallas"
exit $fallas
