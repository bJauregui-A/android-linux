#!/usr/bin/bash
# B23: al extraer la capa, instalar.sh guarda en la instancia el hash de capa.tgz que trae el APK (asset capa.sha256,
# que Instalador pasa en CAPA_SHA256). Así una instancia nueva queda al día y no se vuelve a actualizar.
# Corre en el PC:  pruebas/capa/hash-instalacion.sh
cd "$(dirname "$0")/../.." || exit 1
eval "$(sed -n '/^guardar_hash_capa() {/,/^}/p' apk/instalar.sh)"
type guardar_hash_capa >/dev/null 2>&1 || { echo "FALLA no se encontró guardar_hash_capa en apk/instalar.sh"; exit 1; }
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

E=$T/var/lib/linux-android; mkdir -p "$E"
printf '%064d\n' 7 > "$T/capa.sha256"   # el asset del APK
CAPA_SHA256=$(cat "$T/capa.sha256") guardar_hash_capa
caso "\$E/capa.sha256 queda igual al capa.sha256 del APK"  'cmp -s "$T/capa.sha256" "$E/capa.sha256"'

echo "fallas: $fallas"
[ $fallas -eq 0 ]
