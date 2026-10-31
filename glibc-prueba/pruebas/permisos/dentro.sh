# Pruebas de permisos según el usuario virtual: dueño, grupo y otros (B96). Corre DENTRO de una instancia (probar-en-telefono.sh),
# como el usuario principal. "otro" es www-data (Debian) o http (Arch); root es GLIBC_FAKEROOT=1, como el wrapper de sudo.
D=/tmp/permisos-$$; fallas=0
ok() { echo "OK $1"; }
mal() { echo "FALLA $1: $2"; fallas=$((fallas+1)); }
igual() { [ "$2" = "$3" ] && ok "$1" || mal "$1" "esperaba '$3', salió '$2'"; }
R() { GLIBC_FAKEROOT=1 "$@"; }
OTRO=www-data; id -u $OTRO >/dev/null 2>&1 || OTRO=http
OU=$(id -u $OTRO); OG=$(id -g $OTRO)
como_otro() { R setpriv --regid=$OG --clear-groups setpriv --reuid=$OU "$@"; }   # setpriv baja primero el gid
mkdir -p $D; chmod 755 $D; cd $D
# leer <quién> <archivo> / escribir <quién> <archivo>: salen 0 si abrió, 1 si no. quién: yo, otro
leer() { "$([ "$1" = otro ] && echo como_otro || echo env)" sh -c 'cat "$1" >/dev/null 2>&1' sh "$2"; }
escribir() { "$([ "$1" = otro ] && echo como_otro || echo env)" sh -c 'echo x >> "$1"' sh "$2" 2>/dev/null || return 1; }   # dash da 2 si falla la redirección
# prueba <nombre> <quién> <leer|escribir> <archivo> <0|1> (0: funciona)
puede() { "$3" "$2" "$4"; igual "$1" "$?" "$5"; }
# test -r/-w/-x (faccessat) de <quién> sobre <archivo>
acceso() { if [ "$1" = otro ]; then como_otro /usr/bin/test "$2" "$3"; else /usr/bin/test "$2" "$3"; fi; }

# Paso 0: negar lo que Linux niega al abrir y al consultar
R sh -c ': > r600; echo dato > r600; chmod 600 r600; : > r644; chmod 644 r644'   # de root
echo dato > u600; chmod 600 u600; echo dato > u644; chmod 644 u644               # de user
puede "1. user no lee un 600 de root" yo leer r600 1
puede "2. otro no lee un 600 de user" otro leer u600 1
puede "3. otro no escribe un 644 de user" otro escribir u644 1
puede "3. otro lee un 644 de user" otro leer u644 0
puede "4. user no escribe un 644 de root" yo escribir r644 1
puede "4. user lee un 644 de root" yo leer r644 0
puede "5. user lee su 600" yo leer u600 0
puede "5. user escribe su 600" yo escribir u600 0
# 6. faccessat da lo mismo que open
acceso yo -r r600;   igual "6. test -r de user sobre un 600 de root" "$?" "1"
acceso otro -r u600; igual "6. test -r de otro sobre un 600 de user" "$?" "1"
acceso otro -w u644; igual "6. test -w de otro sobre un 644 de user" "$?" "1"
acceso otro -r u644; igual "6. test -r de otro sobre un 644 de user" "$?" "0"
acceso yo -w r644;   igual "6. test -w de user sobre un 644 de root" "$?" "1"
acceso yo -r r644;   igual "6. test -r de user sobre un 644 de root" "$?" "0"
acceso yo -r u600;   igual "6. test -r de user sobre su 600" "$?" "0"
acceso yo -w u600;   igual "6. test -w de user sobre su 600" "$?" "0"
acceso yo -x u600;   igual "6. test -x de user sobre su 600" "$?" "1"

# Registro (GLIBC_PERMISOS=registro): anota lo que se negaría, pero lo deja pasar
reg() { GLIBC_PERMISOS=registro "$@" 2>reg.err; }
: > reg.err
reg sh -c 'echo x >> r644'
igual "R1. con el registro, user escribe un 644 de root" "$?" "0"
igual "R1. el archivo quedó escrito" "$(R cat r644 | tail -1)" "x"
igual "R1. el registro anota la ruta" "$(grep -c 'permisos.*r644' reg.err)" "1"
igual "R1. el registro anota qué programa fue" "$(grep -c 'permisos.*r644.*exe=.*/sh' reg.err)" "1"
reg cat r600 >/dev/null
igual "R2. con el registro, user lee un 600 de root" "$?" "0"
igual "R2. el registro anota la ruta" "$(grep -c 'permisos.*r600' reg.err)" "1"
: > reg.err; reg sh -c 'echo x >> u600; cat u600 >/dev/null'
igual "R3. lo permitido no deja líneas" "$(wc -l < reg.err)" "0"
sh -c 'echo x >> r644' 2>/dev/null; [ $? -ne 0 ] && r=1 || r=0
igual "R4. sin el registro se niega como siempre" "$r" "1"

cd /; R rm -rf $D
echo "fallas: $fallas"
exit $fallas
