#!/usr/bin/bash
# B11: la app (receptor de depuración) deja el hostname y el hash de la contraseña en $E/ y no en /etc, porque la
# base se extrae después y pisaría /etc/shadow. apk/primer-arranque.sh los pasa a /etc antes de preguntar:
# sembrar_hostname copia $E/hostname si /etc/hostname está vacío; sembrar_hash escribe la línea del usuario en
# /etc/shadow (modo 600) y borra $E/hash.
# Corre en el PC, sobre archivos temporales:  pruebas/usuario/sembrar.sh
cd "$(dirname "$0")/../.." || exit 1
for f in guardar_hash sembrar_hostname sembrar_hash; do
  eval "$(sed -n "/^$f() {/,/^}/p" apk/primer-arranque.sh)"
  type $f >/dev/null 2>&1 || { echo "FALLA no se encontró $f"; exit 1; }
done
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }
d=$(mktemp -d); trap 'rm -rf "$d"' EXIT
export E=$d/E HOSTNAME_ARCHIVO=$d/hostname SHADOW_ARCHIVO=$d/shadow
mkdir -p $E
H='$6$sal$abc/def.ghi'

# hostname
echo mi-equipo > $E/hostname; : > $d/hostname
sembrar_hostname
caso "copia el hostname si /etc/hostname está vacío"   'grep -qx mi-equipo $d/hostname'
echo otro > $d/hostname
sembrar_hostname
caso "no pisa un /etc/hostname que ya tiene nombre"    'grep -qx otro $d/hostname'
rm $E/hostname; : > $d/hostname
sembrar_hostname
caso "sin \$E/hostname no escribe nada"                '[ ! -s $d/hostname ]'

# hash, base de Arch: sin línea del usuario
printf 'root:!*:19000::::::\nbin:!*:19000::::::\n' > $d/shadow
echo "$H" > $E/hash
sembrar_hash ana
caso "agrega la línea del usuario con su hash"         'grep -q "^ana:\$6\$sal\$abc/def.ghi:[0-9]*:0:99999:7:::$" $d/shadow'
caso "deja el shadow en modo 600"                      '[ "$(stat -c %a $d/shadow)" = 600 ]'
caso "borra \$E/hash"                                  '[ ! -e $E/hash ]'
caso "no toca las demás líneas"                        'grep -qx "root:!\*:19000::::::" $d/shadow && [ $(wc -l < $d/shadow) -eq 3 ]'

# hash, usuario ya presente y bloqueado: lo reemplaza sin duplicar
printf 'ana:!:19000:0:99999:7:::\n' > $d/shadow
echo "$H" > $E/hash
sembrar_hash ana
caso "reemplaza la línea bloqueada sin duplicarla"     '[ $(grep -c "^ana:" $d/shadow) -eq 1 ] && grep -q "^ana:\$6\$sal\$abc/def.ghi:" $d/shadow'

# sin $E/hash: no cambia nada
cp $d/shadow $d/s0
sembrar_hash ana
caso "sin \$E/hash no cambia el shadow"                'cmp -s $d/shadow $d/s0'

echo "fallas: $fallas"
[ $fallas -eq 0 ]
