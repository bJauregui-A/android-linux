#!/usr/bin/bash
# B19 + B53: una instancia Debian con el /usr unificado y los usuarios de sistema, como un Debian real. Corre DENTRO de la
# instancia (instala un paquete y lo quita al terminar), desde el PC:
#   scripts/probar-en-telefono.sh <instancia> pruebas/debian/usr-unificado.sh 180
# `sudo` pide contraseña: se la pasa HUMO_CLAVE, como en la batería de humo.
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }
como_root() {
  if [ -n "$HUMO_CLAVE" ]; then printf '%s\n' "$HUMO_CLAVE" | sudo -S -k "$@" 2>&1 | grep -v '^\[sudo\]'; return "${PIPESTATUS[1]}"
  else sudo -n "$@"; fi
}
d=$(mktemp -d); trap 'rm -rf "$d"' EXIT

# El preinst de usr-is-merged rechaza un sistema donde /bin, /sbin o /lib no son enlaces a /usr.
caso "apt-get install --reinstall usr-is-merged termina bien" \
  'como_root apt-get install -y --reinstall usr-is-merged >"$d/merged" 2>&1 || { tail -5 "$d/merged"; false; }'
caso "hostname responde"  '[ -n "$(hostname)" ]'
# uuid-runtime crea su propio usuario (uuidd) en el postinst: pasa por adduser y base-passwd.
previo=; dpkg -s uuid-runtime >/dev/null 2>&1 && previo=1
caso "apt-get install uuid-runtime termina bien" \
  'como_root apt-get install -y uuid-runtime >"$d/uuid" 2>&1 || { tail -5 "$d/uuid"; false; }'
caso "getent passwd uuidd existe"  'getent passwd uuidd >/dev/null'
[ -n "$previo" ] || como_root apt-get remove -y uuid-runtime >/dev/null 2>&1

echo "fallas: $fallas"
[ $fallas -eq 0 ]
