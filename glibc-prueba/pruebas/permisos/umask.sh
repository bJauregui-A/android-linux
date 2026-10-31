# El umask de los procesos de la app es el de Linux (022), no el de Android (077) (B96). Corre DENTRO de una instancia
# (probar-en-telefono.sh), como el usuario principal y como root (GLIBC_FAKEROOT=1).
D=/tmp/umask-$$; fallas=0
ok() { echo "OK $1"; }
mal() { echo "FALLA $1: $2"; fallas=$((fallas+1)); }
igual() { [ "$2" = "$3" ] && ok "$1" || mal "$1" "esperaba '$3', salió '$2'"; }
R() { GLIBC_FAKEROOT=1 "$@"; }
mkdir -p $D; chmod 755 $D; cd $D
igual "umask de user" "$(umask)" "0022"
igual "umask de root" "$(R sh -c umask)" "0022"
touch u; mkdir ud; igual "user crea archivo 644" "$(stat -c %a u)" "644"; igual "user crea carpeta 755" "$(stat -c %a ud)" "755"
R touch r; R mkdir rd; igual "root crea archivo 644" "$(stat -c %a r)" "644"; igual "root crea carpeta 755" "$(stat -c %a rd)" "755"
sh -c 'umask 077; touch p' ; igual "un programa que fija su umask lo conserva" "$(stat -c %a p)" "600"
cd /; R rm -rf $D
echo "fallas: $fallas"
exit $fallas
