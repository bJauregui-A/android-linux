# Pruebas de root que salta los permisos de archivos y carpetas (B95). Corre DENTRO de una instancia (probar-en-telefono.sh).
D=/tmp/root-$$; fallas=0
mkdir -p $D; cd $D
ok() { echo "OK $1"; }
mal() { echo "FALLA $1: $2"; fallas=$((fallas+1)); }
igual() { [ "$2" = "$3" ] && ok "$1" || mal "$1" "esperaba '$3', salió '$2'"; }
R() { GLIBC_FAKEROOT=1 "$@"; }          # como el wrapper de sudo

# Paso 0: leer y escribir sin permiso
echo hola > f000; chmod 000 f000
igual "root lee un 000" "$(R cat f000 2>&1)" "hola"
echo uno > f444; chmod 444 f444
R sh -c 'echo y >> f444' 2>/dev/null; chmod 644 f444
igual "root escribe un 444" "$(cat f444)" "$(printf 'uno\ny')"
mkdir d000; : > d000/dentro; chmod 000 d000
igual "root lista una carpeta 000" "$(R ls d000 2>&1)" "dentro"
mkdir -p dcd/sub; chmod 000 dcd
igual "root entra a una carpeta 000" "$(R sh -c 'cd dcd && pwd' 2>&1)" "$D/dcd"
echo contenido > f444t; chmod 444 f444t
R python3 -c "import os; os.truncate('f444t', 0)" 2>/dev/null   # la syscall truncate, no open
igual "root trunca un 444" "$(stat -c %s f444t)" "0"
R /usr/bin/test -r f000;                     igual "test -r de un 000" "$?" "0"
R /usr/bin/test -w f000;                     igual "test -w de un 000" "$?" "0"
: > f644; chmod 644 f644
R /usr/bin/test -x f644;                     igual "test -x de un 644" "$?" "1"
: > f001; chmod 001 f001
R /usr/bin/test -x f001;                     igual "test -x de un 001" "$?" "0"
R /usr/bin/test -r noexiste;                 igual "test -r de inexistente" "$?" "1"
igual "sin root cat de un 000 falla" "$(cat f000 2>&1 >/dev/null; echo $?)" "$(printf 'cat: f000: Permission denied\n1')"

# Paso 1: crear, borrar y renombrar en una carpeta sin permiso de escritura
own() { stat -c %u:%g "$1"; }
mkdir d555 d555b; : > d555/borrar; mkdir d555/borrard; : > d555/mover; : > d555/orig; : > d555/renombrar
chmod 555 d555 d555b
R mkdir d555/x;                     igual "root crea carpeta en 555" "$(test -d d555/x && echo si)" "si"
R touch d555/f;                     igual "root crea archivo en 555" "$(test -f d555/f && echo si)" "si"
igual "dueño de lo creado en 555" "$(own d555/f)" "0:0"
R ln -s a d555/s;                   igual "root enlace simbólico en 555" "$(readlink d555/s)" "a"
R ln d555/orig d555/h;              igual "root enlace duro en 555" "$(test -f d555/h && echo si)" "si"
R sh -c ': > d555/g';               igual "root crea con > en 555" "$(test -f d555/g && echo si)" "si"
R rm d555/borrar;                   igual "root borra archivo en 555" "$(test -e d555/borrar && echo existe)" ""
R rmdir d555/borrard;               igual "root borra carpeta en 555" "$(test -e d555/borrard && echo existe)" ""
R mv d555/mover d555b/mover;        igual "root mueve entre dos 555" "$(test -f d555b/mover && test ! -e d555/mover && echo si)" "si"
R mv d555/renombrar d555/nuevo;     igual "root renombra en una 555" "$(test -f d555/nuevo && test ! -e d555/renombrar && echo si)" "si"
mkdir d555/y 2>/dev/null;           igual "sin root mkdir en 555 falla" "$(test -e d555/y && echo existe)" ""
chmod 755 d555 d555b
# Paso 2: ejecutar con algún bit x
for m in 111 001 644; do printf '#!/bin/sh\necho corre\n' > p$m; chmod $m p$m; done
igual "root ejecuta un script 111" "$(R ./p111 2>&1)" "corre"
igual "root ejecuta un script 001" "$(R ./p001 2>&1)" "corre"
R ./p644 >/dev/null 2>&1;           igual "root no ejecuta un 644" "$?" "126"
cp /usr/bin/true t111; chmod 111 t111
R ./t111;                           igual "root ejecuta un ELF 111" "$?" "0"
# Paso 3: el modo queda como estaba
modo() { stat -c %a "$1"; }
mkdir m; cd m
echo x > a000; chmod 000 a000;  R cat a000 >/dev/null
echo x > a444; chmod 444 a444;  R sh -c 'echo y >> a444'
mkdir b555 c555 e000; : > b555/f; : > c555/f; : > e000/f; chmod 555 b555 c555; chmod 000 e000
R touch b555/n; R rm b555/f; R mv c555/f c555/g; R ls e000 >/dev/null
printf '#!/bin/sh\n' > a111; chmod 111 a111; R ./a111
printf '#!/bin/sh\n' > a001; chmod 001 a001; R ./a001
cp /usr/bin/true e111; chmod 111 e111; R ./e111
igual "modo de un 000 tras leerlo" "$(modo a000)" "0"
igual "modo de un 444 tras escribirlo" "$(modo a444)" "444"
igual "modo de una 555 tras crear" "$(modo b555)" "555"
igual "modo de una 555 tras borrar" "$(modo c555)" "555"
igual "modo de una 000 tras listarla" "$(modo e000)" "0"
igual "modo de un script 111 tras ejecutarlo" "$(modo a111)" "111"
igual "modo de un script 001 tras ejecutarlo" "$(modo a001)" "1"
igual "modo de un ELF 111 tras ejecutarlo" "$(modo e111)" "111"
mkdir n000; chmod 000 n000
R touch n000/b/f 2>/dev/null
igual "root no crea bajo una 000 sin la intermedia" "$(modo n000)" "0"
mkdir -p q555; chmod 555 q555
R sh -c 'echo x > q555/noexiste/f' 2>/dev/null
igual "modo de una 555 tras ENOENT" "$(modo q555)" "555"
# fuera de la instancia: /data/data lo niega el sandbox de Android (EACCES) y el chmod tampoco se puede; queda el error original
antes=$(stat -c %a /data/data)
igual "fuera de la instancia queda el error" "$(R ls /data/data 2>&1 >/dev/null | grep -c 'Permission denied')" "1"
igual "fuera de la instancia el modo no cambia" "$(stat -c %a /data/data)" "$antes"
chmod 755 b555 c555 e000 n000 q555
cd ..

chmod 755 dcd d000 2>/dev/null
cd /; rm -rf $D
echo "fallas: $fallas"
exit $fallas
