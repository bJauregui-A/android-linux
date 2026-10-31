#!/usr/bin/bash
# B93: probar-en-telefono.sh manda HUMO_CLAVE a la app, en base64, como extra del broadcast. Corre en el PC con un adb falso en el PATH:
#   pruebas/probar/pc.sh
cd "$(dirname "$0")/../.." || exit 1
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
PROBAR=$PWD/scripts/probar-en-telefono.sh

# adb falso: responde como el real y anota el broadcast (un argumento por línea en $e/broadcast) y, si lleva `--es clave X`,
# X decodificado en $e/clave. Con $e/sin-receptor el broadcast falla como cuando la app no está instalada.
entorno() {
  e=$(mktemp -d -p "$tmp"); mkdir "$e/bin"; : > "$e/script"; echo 'echo hola' > "$e/script"
  cat > "$e/bin/adb" <<FALSO
#!/usr/bin/bash
e='$e'
case "\$*" in
  get-state) echo device;;
  "shell am broadcast"*)
    printf '%s\n' "\$@" > "\$e/broadcast"
    while [ \$# -gt 0 ]; do
      if [ "\$1" = clave ]; then printf %s "\$2" | base64 -d > "\$e/clave"; fi
      shift
    done
    if [ -e "\$e/sin-receptor" ]; then echo "Error: Activity class does not exist."; else echo "Broadcast completed: result=0"; fi;;
  *run-as*estado) echo terminado;;
  *run-as*codigo) echo 0;;
  *run-as*salida.log) echo "salida de la prueba";;
esac
FALSO
  chmod +x "$e/bin/adb"
}
# correr [VAR=valor...]: salida (normal y de error) en $e/out, código en $rc
correr() {
  PATH="$e/bin:$PATH" env "$@" "$PROBAR" instancia-x "$e/script" 20 > "$e/out" 2>&1; rc=$?
}

# 1. con HUMO_CLAVE el broadcast lleva --es clave <base64>
entorno; correr HUMO_CLAVE=secreto
caso "con HUMO_CLAVE el broadcast lleva --es clave en base64"  '[ "$(grep -x -B1 -A1 clave "$e/broadcast" | tr "\n" " ")" = "--es clave c2VjcmV0bw== " ]'

# 2. sin HUMO_CLAVE, o vacía, no lleva clave
entorno; correr -u HUMO_CLAVE
caso "sin HUMO_CLAVE el broadcast no lleva clave"  '! grep -qx clave "$e/broadcast"'
entorno; correr HUMO_CLAVE=
caso "con HUMO_CLAVE vacía el broadcast no lleva clave"  '! grep -qx clave "$e/broadcast"'

# 3. una clave con espacios, comillas, $ y ; llega igual
rara='a b "c" '"'d'"' $HOME $(id) ;rm -rf x `y` \ ñ'
entorno; correr HUMO_CLAVE="$rara"
caso "una clave con espacios, comillas, \$ y ; llega igual"  '[ "$(cat "$e/clave")" = "$rara" ]'

# 4. la clave ni su base64 salen en lo que imprime el script, ni en el camino normal ni en el de error
entorno; correr HUMO_CLAVE=secreto
caso "el camino normal no imprime la clave ni su base64"  '! grep -qF -e secreto -e c2VjcmV0bw== "$e/out"'
entorno; touch "$e/sin-receptor"; correr HUMO_CLAVE=secreto
caso "el camino de error no imprime la clave ni su base64"  '[ "$rc" -eq 3 ] && ! grep -qF -e secreto -e c2VjcmV0bw== "$e/out"'

echo "fallas: $fallas"
exit $fallas
