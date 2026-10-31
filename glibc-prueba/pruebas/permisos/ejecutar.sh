# Ejecutar pide x del archivo para quien lo ejecuta, y entrar a una carpeta (cd) pide x de la carpeta (B96, paso 6). Corre DENTRO de una
# instancia (probar-en-telefono.sh), como el usuario principal. "otro" es www-data (Debian) o http (Arch); root es GLIBC_FAKEROOT=1.
D=/tmp/ejecutar-$$; fallas=0
ok() { echo "OK $1"; }
mal() { echo "FALLA $1: $2"; fallas=$((fallas+1)); }
igual() { [ "$2" = "$3" ] && ok "$1" || mal "$1" "esperaba '$3', salió '$2'"; }
R() { GLIBC_FAKEROOT=1 "$@"; }
MIG=$(id -g)
OTRO=www-data; id -u $OTRO >/dev/null 2>&1 || OTRO=http
OU=$(id -u $OTRO); OG=$(id -g $OTRO)
como_otro() { R setpriv --regid=$OG --clear-groups setpriv --reuid=$OU "$@"; }
modo() { stat -c %a "$1"; }
# corre <comando...>: lo que imprime si funciona, o "NO" si no pudo ejecutarlo
corre() { "$@" 2>/dev/null || echo NO; }
mkdir -p $D; chmod 755 $D; cd $D
# un binario ELF (copia de true que imprime algo no hace falta: el código de salida basta) y un script
R cp /usr/bin/true elf; R cp elf b700; R cp elf b755; R cp elf b111; R cp elf b055
R chmod 700 b700; R chmod 755 b755; R chmod 111 b111; R chmod 055 b055
rc() { "$@" >/dev/null 2>&1 && echo 0 || echo 1; }   # 0 si lo ejecutó, 1 si no (setpriv y el shell dan números distintos)

# 26. user ejecuta un binario 700 de root: falla; 755 de root: funciona
igual "26. user no ejecuta un 700 de root" "$(rc ./b700)" "1"
igual "26. user ejecuta un 755 de root" "$(rc ./b755)" "0"
# 28. un ELF 111 lo ejecuta cualquiera (el kernel no necesita leerlo)
igual "28. user ejecuta un ELF 111 de root" "$(rc ./b111)" "0"
igual "28. otro ejecuta un ELF 111 de root" "$(rc como_otro $D/b111)" "0"
# solo x por otros (r-x): el kernel solo mira el dueño (sin x)
igual "26. user ejecuta un ELF 055 de root (otros r-x)" "$(rc ./b055)" "0"

# 27. otro ejecuta un script 750 user:user: falla; 755: funciona
printf '#!/bin/sh\necho corre\n' > s750; printf '#!/bin/sh\necho corre\n' > s755; printf '#!/bin/sh\necho corre\n' > s111
chmod 750 s750; chmod 755 s755; chmod 111 s111
igual "27. otro no ejecuta un script 750 de user:user" "$(rc como_otro $D/s750)" "1"
igual "27. otro ejecuta un script 755 de user" "$(como_otro $D/s755 2>/dev/null)" "corre"
igual "27. user ejecuta su script 750" "$(./s750)" "corre"
# 28. un script 111 no se ejecuta: el intérprete necesita leerlo
igual "28. user no ejecuta un script 111 (sin r)" "$(rc ./s111)" "1"
igual "28. otro no ejecuta un script 111 (sin r)" "$(rc como_otro $D/s111)" "1"
# root ejecuta lo que tenga algún x, y no lo que no tiene ninguno
igual "root ejecuta un ELF 111" "$(rc R ./b111)" "0"
: > n644; chmod 644 n644
igual "root no ejecuta un 644" "$(rc R ./n644)" "1"
# el binario de root 755 en una carpeta sin x para otros
mkdir cd700 cd755; chmod 700 cd700; chmod 755 cd755; R cp elf cd700/b; R chmod 755 cd700/b
igual "27. otro no ejecuta un 755 dentro de una carpeta 700 de user" "$(rc como_otro $D/cd700/b)" "1"

# 29. cd pide x de la carpeta
igual "29. otro no entra (cd) a una carpeta 700 de user" "$(como_otro sh -c "cd $D/cd700 2>/dev/null && echo dentro || echo NO")" "NO"
igual "29. otro entra a una carpeta 755" "$(como_otro sh -c "cd $D/cd755 2>/dev/null && echo dentro || echo NO")" "dentro"
igual "29. user entra a su carpeta 700" "$(sh -c "cd $D/cd700 && echo dentro")" "dentro"
mkdir r055; R chown 0:0 r055; R chmod 055 r055
igual "29. user entra a una carpeta 055 de root (otros r-x)" "$(sh -c "cd $D/r055 2>/dev/null && echo dentro || echo NO")" "dentro"
mkdir cd000; chmod 000 cd000
igual "29. user no entra a una carpeta 000" "$(sh -c "cd $D/cd000 2>/dev/null && echo dentro || echo NO")" "NO"
igual "29. root entra a una carpeta 000" "$(R sh -c "cd $D/cd000 2>/dev/null && echo dentro || echo NO")" "dentro"
mkdir -p g050; R chown 0:$MIG g050; R chmod 050 g050
igual "29. user (grupo) entra a una 050 de root:user" "$(sh -c "cd $D/g050 2>/dev/null && echo dentro || echo NO")" "dentro"

# 15. los modos quedan como estaban
for m in b700:700 b755:755 b111:111 b055:55 s750:750 s111:111 cd700:700 r055:55 cd000:0 g050:50; do
  igual "modo de ${m%:*} queda ${m#*:}" "$(modo ${m%:*})" "${m#*:}"
done

cd /; R chmod -R 755 $D 2>/dev/null; R rm -rf $D
echo "fallas: $fallas"
exit $fallas
