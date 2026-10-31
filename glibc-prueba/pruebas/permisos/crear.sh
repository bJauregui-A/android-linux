# Crear, borrar y renombrar piden w y x en la carpeta padre (B96, paso 5). Corre DENTRO de una instancia (probar-en-telefono.sh), como
# el usuario principal. "otro" es www-data (Debian) o http (Arch); root es GLIBC_FAKEROOT=1.
D=/tmp/crear-$$; fallas=0
ok() { echo "OK $1"; }
mal() { echo "FALLA $1: $2"; fallas=$((fallas+1)); }
igual() { [ "$2" = "$3" ] && ok "$1" || mal "$1" "esperaba '$3', salió '$2'"; }
R() { GLIBC_FAKEROOT=1 "$@"; }
MIG=$(id -g)
OTRO=www-data; id -u $OTRO >/dev/null 2>&1 || OTRO=http
OU=$(id -u $OTRO); OG=$(id -g $OTRO)
como_otro() { R setpriv --regid=$OG --clear-groups setpriv --reuid=$OU "$@"; }
como_otro_en_grupo() { R setpriv --regid=$OG --groups=$MIG setpriv --reuid=$OU "$@"; }
intenta() { "$@" >/dev/null 2>&1 && echo 0 || echo 1; }
modo() { stat -c %a "$1"; }
existe() { { [ -e "$1" ] || [ -L "$1" ]; } && echo si || echo no; }
mkdir -p $D; chmod 755 $D; cd $D

# 20. user no crea en / (755 de root en Debian, 555 en Arch)
igual "20. user no crea un archivo en /" "$(intenta touch /zz-$$) $(existe /zz-$$)" "1 no"
igual "20. user no crea una carpeta en /" "$(intenta mkdir /zd-$$) $(existe /zd-$$)" "1 no"
igual "20. user no crea un enlace simbólico en /" "$(intenta ln -s x /zl-$$) $(existe /zl-$$)" "1 no"
igual "20. root sí crea en /" "$(intenta R touch /zz-$$)" "0"; R rm -f /zz-$$

# 21. user crea y borra en su carpeta personal y en /tmp
igual "21. user crea y borra un archivo en ~" "$(intenta sh -c "touch ~/c-$$ && rm ~/c-$$")" "0"
igual "21. user crea y borra una carpeta en /tmp" "$(intenta sh -c "mkdir /tmp/c-$$ && rmdir /tmp/c-$$")" "0"
igual "21. user crea un enlace y un duro en /tmp" "$(intenta sh -c "touch /tmp/e-$$ && ln -s e /tmp/s-$$ && ln /tmp/e-$$ /tmp/h-$$; r=\$?; rm -f /tmp/e-$$ /tmp/s-$$ /tmp/h-$$; exit \$r")" "0"

# 22. otro no borra un archivo de user en una carpeta 755 de user, ni crea
mkdir d755; echo dato > d755/f; chmod 755 d755
igual "22. otro no borra d755/f" "$(intenta como_otro rm $D/d755/f) $(existe $D/d755/f)" "1 si"
igual "22. otro no crea en d755" "$(intenta como_otro touch $D/d755/nuevo) $(existe $D/d755/nuevo)" "1 no"
igual "22. otro no renombra d755/f" "$(intenta como_otro mv $D/d755/f $D/d755/g) $(existe $D/d755/f)" "1 si"
igual "22. user sí borra y crea en d755" "$(intenta sh -c "touch d755/n && rm d755/n")" "0"

# 23. 775 de root:user: el grupo (user, y otro con user como grupo extra) crea y borra; otro sin el grupo no
R mkdir g775; R chown 0:$MIG g775; R chmod 775 g775
igual "23. user (grupo) crea y borra en g775" "$(intenta sh -c "touch g775/u && rm g775/u")" "0"
igual "23. otro con el grupo extra crea y borra en g775" "$(intenta como_otro_en_grupo sh -c "touch $D/g775/o && rm $D/g775/o")" "0"
igual "23. otro sin el grupo no crea en g775" "$(intenta como_otro touch $D/g775/o) $(existe $D/g775/o)" "1 no"
# el kernel solo mira el dueño (root, 0 de w): 070 de root:user, el grupo puede, y la carpeta vuelve a su modo
R mkdir g070; R chown 0:$MIG g070; R chmod 070 g070
igual "23. 070 de root:user: user (grupo) crea y borra" "$(intenta sh -c "touch g070/u && rm g070/u")" "0"
igual "23. la carpeta 070 queda 70" "$(modo g070)" "70"
igual "23. la carpeta 775 queda 775" "$(modo g775)" "775"

# 24. mv entre dos carpetas pide w en las dos
mkdir ok1 ok2; echo dato > ok1/f
R mkdir rootd; R chmod 755 rootd; R sh -c "echo dato > rootd/f; chmod 666 rootd/f"
igual "24. mv entre dos carpetas del usuario funciona" "$(intenta mv ok1/f ok2/f) $(existe ok2/f)" "0 si"
igual "24. mv a una carpeta de root 755 falla" "$(intenta mv ok2/f rootd/f) $(existe ok2/f)" "1 si"
igual "24. mv desde una carpeta de root 755 falla" "$(intenta mv rootd/f ok1/f) $(existe rootd/f)" "1 si"
igual "24. user no borra rootd/f (aunque sea 666)" "$(intenta rm rootd/f) $(existe rootd/f)" "1 si"
igual "24. user sí agrega a un archivo existente de rootd (666)" "$(intenta sh -c "echo x >> rootd/f")" "0"
igual "24. ln a una carpeta de root 755 falla" "$(intenta ln ok2/f rootd/h) $(existe rootd/h)" "1 no"
igual "24. mknod en una carpeta de root 755 falla" "$(intenta mkfifo rootd/p) $(existe rootd/p)" "1 no"

# 25. los modos de las carpetas quedan como estaban
igual "25. d755 queda 755" "$(modo d755)" "755"
igual "25. rootd queda 755" "$(modo rootd)" "755"
igual "25. / queda como estaba" "$(modo /)" "$(case $(command -v pacman) in '') echo 755;; *) echo 555;; esac)"

cd /; R chmod -R 755 $D 2>/dev/null; R rm -rf $D /zz-$$ /zd-$$ /zl-$$
echo "fallas: $fallas"
exit $fallas
