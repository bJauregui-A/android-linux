#!/usr/bin/bash
# B62: registrar_usuario de apk/primer-arranque.sh deja al usuario con el UID/GID reales de la app,
# aunque la base ya traiga una línea con su nombre y otro UID (la Debian traía user:x:10478).
# Corre en el PC, sobre archivos temporales:  pruebas/usuario/registrar.sh
cd "$(dirname "$0")/../.." || exit 1
eval "$(sed -n '/^registrar_usuario() {/,/^}/p' apk/primer-arranque.sh)"
type registrar_usuario >/dev/null 2>&1 || { echo "FALLA no se encontró registrar_usuario"; exit 1; }
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }
d=$(mktemp -d); trap 'rm -rf "$d"' EXIT
export PASSWD_ARCHIVO=$d/passwd GROUP_ARCHIVO=$d/group

# Base sin el usuario (Arch): lo agrega.
printf 'root:x:0:0:root:/root:/bin/bash\n' > $d/passwd
printf 'root:x:0:\nsudo:x:27:\n' > $d/group
registrar_usuario ana 10479 10479 /usr/bin/zsh
caso "agrega el usuario que falta"          'grep -qx "ana:x:10479:10479:ana:/home/ana:/usr/bin/zsh" $d/passwd'
caso "agrega su grupo"                      'grep -qx "ana:x:10479:" $d/group'

# Base con el usuario y otro UID (Debian): lo corrige sin duplicarlo.
printf 'root:x:0:0:root:/root:/bin/bash\nuser:x:10478:10478:user:/home/user:/bin/bash\n' > $d/passwd
printf 'root:x:0:\nsudo:x:27:user\nuser:x:10478:\n' > $d/group
registrar_usuario user 10479 10479 /bin/bash
caso "corrige el UID y GID del usuario"     'grep -qx "user:x:10479:10479:user:/home/user:/bin/bash" $d/passwd'
caso "no lo duplica"                        '[ $(grep -c "^user:" $d/passwd) -eq 1 ]'
caso "corrige el GID del grupo"             'grep -qx "user:x:10479:" $d/group'
caso "no toca a los demás"                  'grep -qx "root:x:0:0:root:/root:/bin/bash" $d/passwd && grep -qx "sudo:x:27:user" $d/group'

# Segunda pasada: no cambia nada.
cp $d/passwd $d/p0; cp $d/group $d/g0
registrar_usuario user 10479 10479 /bin/bash
caso "es idempotente"                       'cmp -s $d/passwd $d/p0 && cmp -s $d/group $d/g0'

echo "fallas: $fallas"
[ $fallas -eq 0 ]
