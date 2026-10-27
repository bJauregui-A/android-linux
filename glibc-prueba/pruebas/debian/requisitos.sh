#!/usr/bin/bash
# B11: preferences.d/android frena (Pin-Priority -1) paquetes de sistema para que apt no los instale como
# recomendados. Pero un escritorio puede necesitarlos de verdad: cinnamon depende de network-manager-gnome, que
# depende de network-manager, y con el pin apt falla con "not installable" (el nombre que dice apt es el de arriba,
# no el frenado). primer-arranque.sh libera solo los frenados que son requisito real y reintenta.
# Corre en el PC:  pruebas/debian/requisitos.sh
cd "$(dirname "$0")/../.." || exit 1
for f in dependencias_de requisitos_frenados pref_sin; do
  eval "$(sed -n "/^$f() {/,/^}/p" apk/primer-arranque.sh)"
  type $f >/dev/null 2>&1 || { echo "FALLA no se encontró $f en apk/primer-arranque.sh"; exit 1; }
done
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }
d=$(mktemp -d); trap 'rm -rf "$d"' EXIT

cat > "$d/pref" <<'EOF'
Explanation: paquetes de sistema que apt no debe instalar nunca, ni como recomendados
Package: network-manager modemmanager wpasupplicant systemd-sysv plymouth grub* linux-image-* firmware-* bluez cups
Pin: release *
Pin-Priority: -1
EOF

# La salida real de apt al instalar cinnamon (con bluez recomendado pero frenado).
cat > "$d/cinnamon" <<'EOF'
The following packages have unmet dependencies:
 cinnamon : Depends: network-manager-gnome but it is not installable
            Recommends: blueman but it is not installable
E: Unable to correct problems, you have held broken packages.
EOF

# apt-cache depends falso: lo que cuelga de cada paquete (una dependencia por línea, como lo imprime apt-cache).
dependencias_de() {
  case $1 in
    network-manager-gnome) printf '%s\n' libgtk-3-0 network-manager polkit-1-auth-agent ;;
    blueman) printf '%s\n' bluez python3 ;;
    libfoo) printf '%s\n' libbar ;;
  esac
}

caso "cinnamon: libera network-manager (la dependencia de lo que apt dice not installable)" \
  '[ "$(requisitos_frenados "$d/cinnamon" "$d/pref")" = "network-manager" ]'

printf ' foo : Depends: bluez but it is not installable\n' > "$d/directo"
caso "un frenado que apt nombra directo también se libera" \
  '[ "$(requisitos_frenados "$d/directo" "$d/pref")" = "bluez" ]'

printf ' x : Depends: libfoo but it is not installable\n' > "$d/ajeno"
caso "not installable por algo que no está frenado: no libera nada" \
  '[ -z "$(requisitos_frenados "$d/ajeno" "$d/pref")" ]'

printf ' x : Depends: blueman but it is not installable\n' > "$d/reco"
caso "un Depends not installable cuyo paquete depende de un frenado (blueman -> bluez): se libera el frenado" \
  '[ "$(requisitos_frenados "$d/reco" "$d/pref")" = "bluez" ]'

printf ' cinnamon : Recommends: bluez but it is not installable\n' > "$d/soloreco"
caso "una línea Recommends nunca libera nada" \
  '[ -z "$(requisitos_frenados "$d/soloreco" "$d/pref")" ]'

printf 'Reading package lists... Done\n' > "$d/limpio"
caso "salida sin errores: no libera nada" \
  '[ -z "$(requisitos_frenados "$d/limpio" "$d/pref")" ]'

cat "$d/cinnamon" "$d/directo" > "$d/varios"
caso "varios requisitos: uno por línea, sin repetir" \
  '[ "$(requisitos_frenados "$d/varios" "$d/pref" | sort | tr "\n" " ")" = "bluez network-manager " ]'

pref_sin "$d/pref" network-manager > "$d/pref2"
caso "pref_sin quita el paquete de la línea Package" \
  '! sed -n "s/^Package: //p" "$d/pref2" | tr " " "\n" | grep -qxF network-manager'
caso "pref_sin conserva los demás frenados" \
  'sed -n "s/^Package: //p" "$d/pref2" | tr " " "\n" | grep -qxF modemmanager && sed -n "s/^Package: //p" "$d/pref2" | tr " " "\n" | grep -qxF "grub*"'
caso "pref_sin conserva Explanation, Pin y Pin-Priority" \
  'grep -q "^Explanation: " "$d/pref2" && grep -qx "Pin: release \*" "$d/pref2" && grep -qx "Pin-Priority: -1" "$d/pref2"'
caso "pref_sin no quita nombres que solo contienen el liberado (bluez no toca bluez-tools)" \
  'printf "Package: bluez bluez-tools\nPin: release *\nPin-Priority: -1\n" > "$d/p3"; pref_sin "$d/p3" bluez | grep -qx "Package: bluez-tools"'
caso "pref_sin no deja una línea Package vacía" \
  'printf "Package: bluez\nPin: release *\nPin-Priority: -1\n" > "$d/p4"; ! pref_sin "$d/p4" bluez | grep -qx "Package:"'

# Aplicar la liberación sobre el mismo archivo. Un "pref_sin $p | tee $p" lo trunca antes de que sed lo lea y deja
# TODOS los pines fuera (pasó en una instancia de Cinnamon: bajó hasta los paquetes de bluetooth).
# SUDO_CMD=env: la prueba no usa sudo.
eval "$(sed -n '/^liberar_pines() {/,/^}/p' apk/primer-arranque.sh)"
type liberar_pines >/dev/null 2>&1 || { echo "FALLA no se encontró liberar_pines en apk/primer-arranque.sh"; exit 1; }
cp "$d/pref" "$d/real"
SUDO_CMD=env liberar_pines "$d/real" network-manager
caso "liberar_pines sobre el mismo archivo quita solo lo liberado" \
  '! sed -n "s/^Package: //p" "$d/real" | tr " " "\n" | grep -qxF network-manager'
caso "liberar_pines deja los demás pines en su sitio (el archivo no queda vacío)" \
  '[ -s "$d/real" ] && sed -n "s/^Package: //p" "$d/real" | tr " " "\n" | grep -qxF bluez && grep -qx "Pin-Priority: -1" "$d/real"'
caso "liberar_pines no deja archivos temporales" \
  '[ -z "$(ls "${TMPDIR:-/tmp}"/pines.* 2>/dev/null)" ]'

echo "fallas: $fallas"
[ $fallas -eq 0 ]
