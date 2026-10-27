#!/usr/bin/bash
# B67: cada paquete declarado en un escritorios/*/paquetes-debian-12.txt existe en el apt de la instancia
# (apt-cache policy da un Candidate). Solo lectura. Corre en el PC, con una instancia Debian 12:
#   pruebas/debian/paquetes.sh --repo <instancia>
# Arma un script con las listas del repo y lo corre dentro de la instancia con probar-en-telefono.sh.
if [ "$1" = --repo ]; then
    cd "$(dirname "$0")/../.." && t=$(mktemp)
    { echo '#!/usr/bin/bash'; echo "LISTAS=\$(cat <<'FIN'"
      for f in escritorios/*/paquetes-debian-12.txt; do
          id=${f#escritorios/}; id=${id%%/*}
          for p in $(grep -v '^#' "$f"); do echo "$id $p"; done
      done
      echo 'FIN'; echo ')'; cat pruebas/debian/paquetes.sh; } > "$t"
    scripts/probar-en-telefono.sh "$2" "$t" 120; r=$?; rm -f "$t"; exit $r
fi
[ -n "$LISTAS" ] || { echo "FALLA sin listas: correr con --repo <instancia> desde el PC"; exit 1; }
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }
candidato() { apt-cache policy "$1" 2>/dev/null | sed -n 's/^ *Candidate: //p'; }
while read -r id p; do
    c=$(candidato "$p")
    caso "$id: $p (${c:-no existe})" '[ -n "$c" ] && [ "$c" != "(none)" ]'
done <<<"$LISTAS"
echo "fallas: $fallas"
[ $fallas -eq 0 ]
