#!/usr/bin/bash
# B62: activar_sudo de apk/primer-arranque.sh deja la regla final aunque haya LD_LIBRARY_PATH
# (como en la instalación). Corre dentro de una instancia, como el usuario principal:
#   scripts/probar-en-telefono.sh <instancia> pruebas/sudo/instalador.sh   (la del primer-arranque instalado)
#   pruebas/sudo/instalador.sh --repo <instancia>                          (la de apk/primer-arranque.sh)
# Usa una regla aparte (99-prueba-b62) y la borra al terminar.
if [ "$1" = --repo ]; then
    # En el PC: antepone la función del repo y corre esta prueba dentro de la instancia.
    cd "$(dirname "$0")/../.." && t=$(mktemp)
    { echo '#!/usr/bin/bash'; sed -n '/^activar_sudo() {/,/^}/p' apk/primer-arranque.sh; cat pruebas/sudo/instalador.sh; } > "$t"
    scripts/probar-en-telefono.sh "$2" "$t" 60; r=$?; rm -f "$t"; exit $r
fi
PA=/usr/local/share/linux-android/primer-arranque.sh
[ -f "$PA" ] || PA=/usr/local/share/arch-android/primer-arranque.sh
[ -n "$PRIMER_ARRANQUE" ] && PA=$PRIMER_ARRANQUE
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }

SUDOERS=/etc/sudoers.d/99-prueba-b62
N=$(id -un)
export LD_LIBRARY_PATH=${LD_LIBRARY_PATH:-/usr/lib}
# Si ya viene definida (versión del repo antepuesta al script), se usa esa.
type activar_sudo >/dev/null 2>&1 || eval "$(sed -n '/^activar_sudo() {/,/^}/p' "$PA")"
type activar_sudo >/dev/null 2>&1 || { echo "FALLA no se encontró activar_sudo en $PA"; exit 1; }

activar_sudo; rc=$?
caso "activar_sudo termina bien"            '[ $rc -eq 0 ]'
caso "queda la regla final"                 '[ -f $SUDOERS ]'
caso "no queda el .nuevo"                   '[ ! -e $SUDOERS.nuevo ]'
caso "la regla es del usuario"              'grep -qx "$N ALL=(ALL:ALL) ALL" $SUDOERS 2>/dev/null'
caso "conserva LD_LIBRARY_PATH"             'grep -q "env_keep += \"LD_LIBRARY_PATH\"" $SUDOERS 2>/dev/null'
caso "modo 440 y dueño root"                '[ "$(stat -c "%a %u %g" $SUDOERS 2>/dev/null)" = "440 0 0" ]'
caso "sudo la acepta (visudo -c)"           'GLIBC_FAKEROOT=1 visudo -cf $SUDOERS >/dev/null 2>&1 || ! command -v visudo >/dev/null'

# En una terminal (como en kitty), sudo abre su propia pty (use_pty) y Android no lo deja.
NP=/etc/sudoers.d/99-prueba-b62-np
printf '%s ALL=(root) NOPASSWD: /usr/bin/id\n' "$N" | GLIBC_FAKEROOT=1 tee $NP >/dev/null
GLIBC_FAKEROOT=1 chmod 440 $NP
salida_tty=$(script -qec "sudo -n /usr/bin/id -u" /dev/null 2>&1 | tr -d '\r')
caso "sudo en una terminal (pty)"           '[ "$salida_tty" = 0 ] || { echo "      $salida_tty"; false; }'

GLIBC_FAKEROOT=1 rm -f $SUDOERS $SUDOERS.nuevo $NP
echo "fallas: $fallas"
[ $fallas -eq 0 ]
