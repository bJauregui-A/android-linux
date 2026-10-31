# Las carpetas /tmp, /home, /mnt, /media y /var/tmp son de root y de modo 1777 las temporales (B96, paso 1). Corre DENTRO de una
# instancia (probar-en-telefono.sh), como el usuario principal.
D=/tmp/zonas-$$; fallas=0
ok() { echo "OK $1"; }
mal() { echo "FALLA $1: $2"; fallas=$((fallas+1)); }
igual() { [ "$2" = "$3" ] && ok "$1" || mal "$1" "esperaba '$3', salió '$2'"; }
YO=$(id -un):$(id -gn)
for d in /tmp /home /mnt /media /var/tmp; do
  if [ -d $d ]; then igual "3. $d es de root:root" "$(stat -c %U:%G $d)" "root:root"
  else echo "SALTA 3. $d no existe en esta distro"; fi
done
# Debian trae /mnt y /media; Arch no trae /media
if command -v apt-get >/dev/null 2>&1; then
  for d in /mnt /media; do [ -d $d ] && ok "3. Debian trae $d" || mal "3. Debian trae $d" "no existe"; done
fi
mkdir -p $D; cd $D
touch /tmp/zonas-$$-f; igual "4. un archivo en /tmp es del usuario" "$(stat -c %U:%G /tmp/zonas-$$-f)" "$YO"; rm -f /tmp/zonas-$$-f
touch /var/tmp/zonas-$$-f; igual "4. un archivo en /var/tmp es del usuario" "$(stat -c %U:%G /var/tmp/zonas-$$-f)" "$YO"; rm -f /var/tmp/zonas-$$-f
igual "4. la carpeta personal es del usuario" "$(stat -c %U:%G $HOME)" "$YO"
igual "4. /tmp/<carpeta> es del usuario" "$(stat -c %U:%G $D)" "$YO"
igual "5. /tmp es 1777" "$(stat -c %a /tmp)" "1777"
igual "5. /var/tmp es 1777" "$(stat -c %a /var/tmp)" "1777"
cd /; rm -rf $D
echo "fallas: $fallas"
exit $fallas
