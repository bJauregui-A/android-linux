# Pruebas del sudo real (B27 fase 3). Corre DENTRO de una instancia con el paquete sudo (probar-en-telefono.sh).
# Crea el usuario `prueba` y /etc/sudoers.d/zz-prueba; los borra al terminar.
fallas=0
ok() { echo "OK $1"; }
mal() { echo "FALLA $1: $2"; fallas=$((fallas+1)); }
igual() { [ "$2" = "$3" ] && ok "$1" || mal "$1" "esperaba '$3', salió '$2'"; }
R() { GLIBC_FAKEROOT=1 "$@"; }
[ -u /usr/bin/sudo ] || { echo "FALLA: /usr/bin/sudo no es setuid (¿paquete sudo?)"; exit 1; }
rm -f /usr/local/bin/sudo; hash -r   # la APK vieja lo reescribe al abrir; la nueva no, con la marca 10-linux-android
R userdel -r prueba 2>/dev/null; R rm -f /etc/sudoers.d/zz-prueba
R useradd -m prueba && R sh -c 'echo prueba:clave123 | chpasswd' || mal "useradd/chpasswd" "falló"
# Debian no usa ld.so.cache: sin LD_LIBRARY_PATH los programas no encuentran sus bibliotecas y sudo la borra (env_reset)
R sh -c 'rm -f /etc/sudoers.d/zz-prueba-env; [ -z "$LD_LIBRARY_PATH" ] || { echo "Defaults env_keep += \"LD_LIBRARY_PATH\"" > /etc/sudoers.d/zz-prueba-env; chmod 440 /etc/sudoers.d/zz-prueba-env; }'
U=$(id -u prueba); G=$(id -g prueba)
R sh -c 'echo "prueba ALL=(ALL:ALL) ALL" > /etc/sudoers.d/zz-prueba; chmod 440 /etc/sudoers.d/zz-prueba'
como() { R setpriv --regid=$G --clear-groups setpriv --reuid=$U "$@"; }   # setpriv baja primero el gid (sin KEEPCAPS)
igual "como prueba" "$(como id -u)" "$U"
igual "clave correcta" "$(echo clave123 | como sudo -S -k id -u 2>/dev/null)" "0"
echo clave123 | como sudo -S -k true 2>/dev/null; igual "salida 0 con clave correcta" "$?" "0"
echo mala | como sudo -S -k true >/dev/null 2>&1; igual "clave mala rechazada" "$?" "1"
como sudo -n -k true >/dev/null 2>&1; igual "sin clave y -n rechazado" "$?" "1"
id -u nobody >/dev/null 2>&1 && igual "-u nobody" "$(echo clave123 | como sudo -S -k -u nobody id -un 2>/dev/null)" "nobody"   # Debian de la app no trae nobody (B53)
igual "-u root" "$(echo clave123 | como sudo -S -k -u root id -un 2>/dev/null)" "root"
igual "-i (shell de login)" "$(echo clave123 | como sudo -S -k -i id -un 2>/dev/null)" "root"
igual "ruid de SUDO_UID" "$(echo clave123 | como sudo -S -k sh -c 'echo $SUDO_UID' 2>/dev/null)" "$U"
igual "-l lista" "$(echo clave123 | como sudo -S -k -l 2>/dev/null | grep -c 'ALL')" "1"
R sh -c 'rm -f /etc/sudoers.d/zz-prueba; echo "prueba ALL=(root) NOPASSWD: /usr/bin/id" > /etc/sudoers.d/zz-prueba; chmod 666 /etc/sudoers.d/zz-prueba'
como sudo -n id >/dev/null 2>&1; igual "NOPASSWD con permisos 666 (sudoers mal: rechaza)" "$?" "1"
R chmod 440 /etc/sudoers.d/zz-prueba
igual "NOPASSWD solo id" "$(como sudo -n id -u 2>/dev/null)" "0"
como sudo -n true >/dev/null 2>&1; igual "comando fuera de la regla" "$?" "1"
R userdel -r prueba 2>/dev/null; R rm -f /etc/sudoers.d/zz-prueba /etc/sudoers.d/zz-prueba-env
echo "fallas: $fallas"; exit $fallas
