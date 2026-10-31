# Cada carpeta del camino necesita x para quien recorre la ruta (B96, paso 4). Corre DENTRO de una instancia (probar-en-telefono.sh),
# como el usuario principal. "otro" es www-data (Debian) o http (Arch); root es GLIBC_FAKEROOT=1.
D=/tmp/camino-$$; fallas=0
ok() { echo "OK $1"; }
mal() { echo "FALLA $1: $2"; fallas=$((fallas+1)); }
igual() { [ "$2" = "$3" ] && ok "$1" || mal "$1" "esperaba '$3', salió '$2'"; }
R() { GLIBC_FAKEROOT=1 "$@"; }
OTRO=www-data; id -u $OTRO >/dev/null 2>&1 || OTRO=http
OU=$(id -u $OTRO); OG=$(id -g $OTRO)
como_otro() { R setpriv --regid=$OG --clear-groups setpriv --reuid=$OU "$@"; }
intenta() { "$@" >/dev/null 2>&1 && echo 0 || echo 1; }
modo() { stat -c %a "$1"; }
mkdir -p $D; chmod 755 $D; cd $D
mkdir d700 d711 d744 d000 d755; for d in d700 d711 d744 d000 d755; do echo dato > $d/f; chmod 644 $d/f; done
chmod 700 d700; chmod 711 d711; chmod 744 d744; chmod 000 d000

igual "16. otro no abre d700/f (f es 644)" "$(intenta como_otro cat $D/d700/f)" "1"
igual "16. user abre d700/f (es suya)" "$(intenta cat $D/d700/f)" "0"
igual "17. otro abre d711/f" "$(intenta como_otro cat $D/d711/f)" "0"
igual "17. otro abre d755/f" "$(intenta como_otro cat $D/d755/f)" "0"
igual "18. otro lista los nombres de d744" "$(como_otro ls $D/d744 2>/dev/null)" "f"
igual "18. otro no abre d744/f" "$(intenta como_otro cat $D/d744/f)" "1"
igual "19. user no abre d000/f" "$(intenta cat $D/d000/f)" "1"
igual "19. root abre d000/f" "$(intenta R cat $D/d000/f)" "0"
igual "faccessat: otro test -r d700/f" "$(intenta como_otro /usr/bin/test -r $D/d700/f)" "1"
igual "faccessat: otro test -r d711/f" "$(intenta como_otro /usr/bin/test -r $D/d711/f)" "0"
igual "truncate: otro no trunca d700/f" "$(como_otro truncate -s 0 $D/d700/f 2>/dev/null; stat -c %s $D/d700/f)" "5"

# stat también recorre el camino
igual "stat: otro no ve d700/f" "$(intenta como_otro stat $D/d700/f)" "1"
igual "stat: otro ve d711/f" "$(intenta como_otro stat $D/d711/f)" "0"
igual "stat: otro ve la propia carpeta d700 (no hace falta x en ella)" "$(intenta como_otro stat $D/d700)" "0"
igual "stat: user ve d000 pero no d000/f" "$(intenta stat $D/d000) $(intenta stat $D/d000/f)" "0 1"
igual "stat: root ve d000/f" "$(intenta R stat $D/d000/f)" "0"
igual "fstat de un fd abierto no mira el camino" "$(como_otro sh -c 'exec 3< $0; stat -L /proc/self/fd/3 >/dev/null 2>&1; echo $?' $D/d711/f)" "0"

# rutas relativas: se mira la carpeta desde la que se busca y lo de adentro, no lo de arriba
igual "relativa: otro desde $D no abre d700/f" "$(intenta como_otro cat d700/f)" "1"
igual "relativa: otro desde $D abre d711/f" "$(intenta como_otro cat d711/f)" "0"
cd d700; igual "relativa: otro con cwd en d700 no abre f" "$(intenta como_otro cat f)" "1"; cd ..
mkdir -p a700/b755; echo dato > a700/b755/f; chmod 644 a700/b755/f; chmod 700 a700
cd a700/b755; igual "relativa: lo que hay por encima del cwd no se mira" "$(intenta como_otro cat f)" "0"; cd ../..
igual "absoluta: la misma carpeta sí se mira" "$(intenta como_otro cat $D/a700/b755/f)" "1"

# el kernel niega x (solo mira los bits del dueño) pero Linux lo permite por otros: se concede un instante
R mkdir $D/r055; R sh -c "echo dato > $D/r055/f; chmod 644 $D/r055/f; chmod 055 $D/r055"
igual "concesión: user abre r055/f (otros r-x)" "$(intenta cat $D/r055/f)" "0"
igual "concesión: la carpeta queda 055" "$(modo $D/r055)" "55"
R mkdir $D/r750; R sh -c "echo dato > $D/r750/f; chmod 644 $D/r750/f; chmod 750 $D/r750"
igual "root:otros 750: user sin grupo no pasa" "$(intenta cat $D/r750/f)" "1"
igual "la carpeta queda 750" "$(modo $D/r750)" "750"

igual "modo: d700 queda 700" "$(modo $D/d700)" "700"
igual "modo: d000 queda 0" "$(modo $D/d000)" "0"
cd /; R chmod -R 755 $D; R rm -rf $D
echo "fallas: $fallas"
exit $fallas
