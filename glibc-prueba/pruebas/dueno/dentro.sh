# Pruebas del dueño persistente (B27 fase 2). Corre DENTRO de una instancia (probar-en-telefono.sh).
D=/tmp/dueno-$$; fallas=0
mkdir -p $D; cd $D
ok() { echo "OK $1"; }
mal() { echo "FALLA $1: $2"; fallas=$((fallas+1)); }
igual() { [ "$2" = "$3" ] && ok "$1" || mal "$1" "esperaba '$3', salió '$2'"; }
own() { stat -c %u:%g "$1"; }
R() { GLIBC_FAKEROOT=1 "$@"; }          # como el wrapper de sudo
ME=$(id -u):$(id -g)

: > a; igual "nuevo del principal" "$(own a)" "$ME"
R chown 1234:5678 a;                igual "chown guarda" "$(own a)" "1234:5678"
R chown :99 a;                      igual "chown solo grupo" "$(own a)" "1234:99"
R chown 0:0 a;                      igual "chown a root" "$(own a)" "0:0"
R chown -h 7:8 a;                   igual "chown -h (lchown)" "$(own a)" "7:8"
chmod 444 a; R chown 11:12 a;       igual "chown en 0444" "$(own a)" "11:12"
igual "modo intacto" "$(stat -c %a a)" "444"
chown 5:6 a 2>/dev/null;            igual "sin privilegio no cambia" "$(own a)" "11:12"
R chown $ME a;                      igual "chown al principal" "$(own a)" "$ME"
mkdir d; R chown -R 21:22 d;        igual "chown de carpeta" "$(own d)" "21:22"
ln -s a s; R chown -h 31:32 s;      igual "lchown de enlace no falla" "$?" "0"
R chown 1:1 noexiste 2>/dev/null;   igual "chown de inexistente falla" "$?" "1"
# archivo con xattr viaja por rename y cp -a
: > b; R chown 41:42 b; mv b c;     igual "rename conserva" "$(own c)" "41:42"
R cp -a c e;                        igual "cp -a conserva" "$(own e)" "41:42"
# fchown (install -o/-g usa fchown)
R install -m 600 -o 51 -g 52 /dev/null f; igual "install -o -g" "$(own f)" "51:52"
# archivos nuevos según el fsuid (setpriv baja primero el gid: con --reuid antes perdería el privilegio, falta PR_SET_KEEPCAPS)
R setpriv --regid=62 --clear-groups setpriv --reuid=61 touch n1; igual "nuevo de otro usuario" "$(own n1)" "61:62"
R setpriv --regid=62 --clear-groups setpriv --reuid=61 mkdir n2;  igual "carpeta nueva de otro usuario" "$(own n2)" "61:62"
R touch n3;                         igual "nuevo de root" "$(own n3)" "0:0"
echo x > n4; R sh -c 'echo y >> n4'; igual "abrir existente no cambia dueño" "$(own n4)" "$ME"
R sh -c ': > n5';                   igual "root crea con >" "$(own n5)" "0:0"
# enlaces duros (cerrojo de shadow)
: > h1; ln h1 h2
igual "nlink 2 con el par" "$(stat -c %h h1)" "2"
igual "nlink 2 en la otra copia" "$(stat -c %h h2)" "2"
rm h2;                              igual "nlink 1 al borrar el par" "$(stat -c %h h1)" "1"
R chown 71:72 h1; ln h1 h3;         igual "enlace conserva dueño" "$(own h3)" "71:72"
# lo que pide shadow
if command -v groupadd >/dev/null; then
  g=prueba$$
  R groupadd $g;                    igual "groupadd" "$?" "0"
  R groupdel $g;                    igual "groupdel" "$?" "0"
fi
cd /; rm -rf $D
echo "fallas: $fallas"
exit $fallas
