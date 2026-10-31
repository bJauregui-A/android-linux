# El bit sticky: en una carpeta 1777 solo borra, renombra o pisa quien es dueño del archivo o de la carpeta (B96, paso 7). Corre DENTRO de una
# instancia (probar-en-telefono.sh), como el usuario principal. "otro" es www-data (Debian) o http (Arch); root es GLIBC_FAKEROOT=1.
D=/tmp/sticky-$$; fallas=0
ok() { echo "OK $1"; }
mal() { echo "FALLA $1: $2"; fallas=$((fallas+1)); }
igual() { [ "$2" = "$3" ] && ok "$1" || mal "$1" "esperaba '$3', salió '$2'"; }
R() { GLIBC_FAKEROOT=1 "$@"; }
OTRO=www-data; id -u $OTRO >/dev/null 2>&1 || OTRO=http
OU=$(id -u $OTRO); OG=$(id -g $OTRO)
como_otro() { R setpriv --regid=$OG --clear-groups setpriv --reuid=$OU "$@"; }
intenta() { "$@" >/dev/null 2>&1 && echo 0 || echo 1; }
existe() { { [ -e "$1" ] || [ -L "$1" ]; } && echo si || echo no; }
modo() { stat -c %a "$1"; }
mkdir -p $D; chmod 755 $D; cd $D
mkdir pegajosa; chmod 1777 pegajosa          # del usuario principal, con sticky
S=$D/pegajosa
echo u > $S/u; como_otro sh -c "echo o > $S/o"

# 30. otro no borra, renombra ni pisa lo de user; user borra lo suyo
igual "30. otro no borra un archivo de user" "$(intenta como_otro rm $S/u) $(existe $S/u)" "1 si"
igual "30. otro no renombra un archivo de user" "$(intenta como_otro mv $S/u $S/u2) $(existe $S/u)" "1 si"
igual "30. otro no pisa un archivo de user con mv" "$(intenta como_otro mv $S/o $S/u) $(existe $S/o)" "1 si"
igual "30. el archivo de user sigue con su contenido" "$(cat $S/u)" "u"
igual "30. otro borra lo suyo" "$(intenta como_otro rm $S/o) $(existe $S/o)" "0 no"
como_otro sh -c "echo o > $S/o"
igual "30. otro renombra lo suyo" "$(intenta como_otro mv $S/o $S/o2) $(existe $S/o2)" "0 si"
igual "30. user borra lo suyo" "$(intenta rm $S/u) $(existe $S/u)" "0 no"

# 31. el dueño de la carpeta sticky borra lo de otros; root también
igual "31. el dueño de la carpeta borra lo de otro" "$(intenta rm $S/o2) $(existe $S/o2)" "0 no"
como_otro sh -c "echo o > $S/o"
igual "31. root borra lo de otro" "$(intenta R rm $S/o) $(existe $S/o)" "0 no"
# /tmp es de root, con sticky: user no borra lo de otro
como_otro sh -c "echo o > /tmp/sticky-$$-o"
igual "31. /tmp: user no borra lo de otro" "$(intenta rm /tmp/sticky-$$-o) $(existe /tmp/sticky-$$-o)" "1 si"
igual "31. /tmp: otro borra lo suyo" "$(intenta como_otro rm /tmp/sticky-$$-o) $(existe /tmp/sticky-$$-o)" "0 no"
echo u > /tmp/sticky-$$-u
igual "31. /tmp: otro no borra lo de user" "$(intenta como_otro rm /tmp/sticky-$$-u) $(existe /tmp/sticky-$$-u)" "1 si"
igual "31. /tmp: user borra lo suyo" "$(intenta rm /tmp/sticky-$$-u) $(existe /tmp/sticky-$$-u)" "0 no"
R rm -f /tmp/sticky-$$-o /tmp/sticky-$$-u

# 32. sin sticky, en una 777: otro borra lo de user
mkdir libre; chmod 777 libre; echo u > libre/u
igual "32. 777 sin sticky: otro borra lo de user" "$(intenta como_otro rm $D/libre/u) $(existe $D/libre/u)" "0 no"
echo u > libre/u
igual "32. 777 sin sticky: otro renombra lo de user" "$(intenta como_otro mv $D/libre/u $D/libre/v) $(existe $D/libre/v)" "0 si"

# un directorio también: rmdir y rename de carpetas
mkdir $S/dir_user; como_otro mkdir $S/dir_otro
igual "rmdir: otro no borra la carpeta de user" "$(intenta como_otro rmdir $S/dir_user) $(existe $S/dir_user)" "1 si"
igual "rmdir: otro borra su carpeta" "$(intenta como_otro rmdir $S/dir_otro) $(existe $S/dir_otro)" "0 no"
igual "mv: user renombra su carpeta" "$(intenta mv $S/dir_user $S/dir_user2) $(existe $S/dir_user2)" "0 si"

igual "la carpeta sticky queda 1777" "$(modo $S)" "1777"
cd /; R chmod -R 777 $D 2>/dev/null; R rm -rf $D
echo "fallas: $fallas"
exit $fallas
