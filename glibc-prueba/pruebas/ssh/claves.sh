#!/usr/bin/bash
# sshd sin claves de host termina con "no hostkeys available": pasa si openssh se instaló después del primer
# arranque (sin el opcional ssh), porque aquí no hay sshdgenkeys.service de systemd que las cree.
# Corre en el PC, sobre las carpetas reales del repo:  pruebas/ssh/claves.sh
cd "$(dirname "$0")/../.." || exit 1
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }
AUTO=escritorios/autostart-android
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# autostart-android: ssh-keygen -A (solo crea las que faltan) antes de arrancar sshd.
claves=$(grep -n 'ssh-keygen -A' $AUTO | head -1 | cut -d: -f1)
arranque=$(grep -n '^ *iniciar sshd ' $AUTO | head -1 | cut -d: -f1)
caso "el escritorio genera las claves que falten"  '[ -n "$claves" ]'
caso "las genera antes de arrancar sshd"  '[ -n "$claves" ] && [ -n "$arranque" ] && [ "$claves" -lt "$arranque" ]'

# Supervisor (service enable ssh): la unidad de sshd genera las claves antes de todo, incluso del
# "sshd -t" de Debian, que también falla sin claves.
cat > "$tmp/ver.c" <<'EOF'
#include <stdio.h>
#include "unidad.h"
int main(int argc, char **argv) {
    Unidad u;
    if (unidad_cargar(argv[1], &u) != 0) return 2;
    printf("%s\n", u.exec_pre);
    return 0;
}
EOF
gcc -O2 -w -Isupervisor -o "$tmp/ver" "$tmp/ver.c" supervisor/unidad.c supervisor/common.c || exit 1

arch="$tmp/arch"; mkdir -p "$arch/usr/lib/systemd/system"
printf '[Service]\nExecStart=/usr/bin/sshd -D\n' > "$arch/usr/lib/systemd/system/sshd.service"
pre=$(SERVICE_ROOT=$arch "$tmp/ver" ssh)
caso "Arch: la unidad sshd genera las claves"  '[[ "$pre" == *"ssh-keygen -A"* ]]'

deb="$tmp/deb"; mkdir -p "$deb/lib/systemd/system"
printf '[Service]\nExecStartPre=/usr/sbin/sshd -t\nExecStart=/usr/sbin/sshd -D $SSHD_OPTS\n' \
    > "$deb/lib/systemd/system/ssh.service"
pre=$(SERVICE_ROOT=$deb "$tmp/ver" ssh)
caso "Debian: genera las claves antes de sshd -t"  '[[ "$pre" == *"ssh-keygen -A"*"sshd -t"* ]]'

otro="$tmp/otro"; mkdir -p "$otro/usr/lib/systemd/system"
printf '[Service]\nExecStart=/usr/bin/nginx\n' > "$otro/usr/lib/systemd/system/nginx.service"
pre=$(SERVICE_ROOT=$otro "$tmp/ver" nginx)
caso "otros servicios no generan claves"  '[[ "$pre" != *ssh-keygen* ]]'

echo "fallas: $fallas"
[ "$fallas" -eq 0 ]
