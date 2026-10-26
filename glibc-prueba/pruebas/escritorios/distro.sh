#!/usr/bin/bash
# B67: distro_version de apk/primer-arranque.sh saca de /etc/os-release la distro y versión con que se
# eligen paquetes y estado de los escritorios (debian-12, arch...).
# Corre en el PC, sobre archivos temporales:  pruebas/escritorios/distro.sh
cd "$(dirname "$0")/../.." || exit 1
eval "$(sed -n '/^distro_version() {/,/^}/p' apk/primer-arranque.sh)"
type distro_version >/dev/null 2>&1 || { echo "FALLA no se encontró distro_version"; exit 1; }
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }
d=$(mktemp -d); trap 'rm -rf "$d"' EXIT
export OS_RELEASE_ARCHIVO=$d/os-release

printf 'PRETTY_NAME="Debian GNU/Linux 12 (bookworm)"\nVERSION_ID="12"\nID=debian\n' > $OS_RELEASE_ARCHIVO
caso "Debian 12 es debian-12"               '[ "$(distro_version)" = debian-12 ]'

printf 'NAME="Arch Linux ARM"\nPRETTY_NAME="Arch Linux ARM"\nID=archarm\nID_LIKE=arch\n' > $OS_RELEASE_ARCHIVO
caso "Arch ARM (rolling, sin versión) es arch"  '[ "$(distro_version)" = arch ]'

# La base de Arch trae /usr/lib/os-release pero no el enlace /etc/os-release (lo crea el paquete filesystem durante la
# instalación): al elegir paquetes aún no existe, DISTRO salía "-" y no entraban los paquetes del escritorio.
export OS_RELEASE_ARCHIVO=$d/no-existe OS_RELEASE_RESPALDO=$d/usr-lib-os-release
printf 'NAME="Arch Linux ARM"\nID=archarm\nID_LIKE=arch\n' > $OS_RELEASE_RESPALDO
caso "sin /etc/os-release usa el de /usr/lib (Arch)"  '[ "$(distro_version)" = arch ]'
printf 'VERSION_ID="12"\nID=debian\n' > $OS_RELEASE_RESPALDO
caso "sin /etc/os-release usa el de /usr/lib (Debian)"  '[ "$(distro_version)" = debian-12 ]'

echo "fallas: $fallas"
[ $fallas -eq 0 ]
