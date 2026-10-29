#!/usr/bin/bash
# B17: la lógica de estaticos.sh (descarga, sha256, SALTA) con binarios falsos. Corre en el PC:
#   pruebas/estaticos/pc.sh
cd "$(dirname "$0")/../.." || exit 1
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
ESTATICOS=$PWD/pruebas/estaticos/estaticos.sh

falso() { printf '#!/bin/sh\n%s\n' "$2" > "$e/bin/$1"; chmod +x "$e/bin/$1"; }
# Entorno nuevo: bin/ con las herramientas básicas y un curl falso que anota sus argumentos y deja en $e/fuente el archivo
# que "baja" (sale con 1 si no hay fuente). El rg falso anota en $e/ejecutado que corrió.
entorno() {
  e=$(mktemp -d -p "$tmp"); mkdir "$e/bin" "$e/cache" "$e/paq"; : > "$e/log"
  for c in bash env timeout grep cat mktemp rm sleep sed date mkdir touch wc tee head tr ls chmod printf tar gzip sha256sum \
           find mv cp basename dirname pgrep uniq cut seq; do
    ln -s "$(command -v "$c")" "$e/bin/$c"
  done
  falso curl 'echo "curl $*" >> '"$e"'/log
while [ $# -gt 1 ]; do [ "$1" = -o ] && { salida=$2; break; }; shift; done
[ -e '"$e"'/fuente ] || exit 1
cp '"$e"'/fuente "$salida"'
  printf '#!/bin/sh\necho corrio >> %s/ejecutado\n' "$e" > "$e/paq/rg"; chmod +x "$e/paq/rg"
  tar -czf "$e/paq/rg.tar.gz" -C "$e/paq" rg
  sha=$(sha256sum "$e/paq/rg.tar.gz" | cut -d' ' -f1)
  printf 'rg https://bajadas.test/rg.tar.gz %s rg\n' "$sha" > "$e/tabla"
}
# correr [VAR=valor...]: entorno limpio; salida en $e/out, código en $rc
correr() {
  /usr/bin/env -i PATH="$e/bin" ESTATICOS_SOLO=rg ESTATICOS_TABLA="$e/tabla" ESTATICOS_CACHE="$e/cache" "$@" \
    /usr/bin/bash "$ESTATICOS" > "$e/out" 2>&1; rc=$?
}
linea() { grep -E "^$1 +.*$2" "$e/out"; }

# 1. sha distinto: FALLA y el binario no se ejecuta
entorno; echo otra-cosa > "$e/fuente"; correr
caso "sha distinto: la línea del binario es FALLA"  'linea FALLA "rg" >/dev/null'
caso "sha distinto: sale distinto de 0 y no ejecuta el binario"  '[ "$rc" -ne 0 ] && [ ! -e "$e/ejecutado" ]'

# 2. sin red: los casos del binario son SALTA sin red y fallas no sube
entorno; correr
caso "sin red: la línea del binario es SALTA sin red"  'linea SALTA "sin red" >/dev/null'
caso "sin red: fallas: 0 y sale con 0"  'grep -q "^fallas: 0" "$e/out" && [ "$rc" -eq 0 ]'

# 3. ya bajado con sha correcto: no se vuelve a bajar
entorno; cp "$e/paq/rg.tar.gz" "$e/fuente"; correr
caso "primera vez: curl baja el archivo"  '[ "$(grep -c "^curl" "$e/log")" -eq 1 ] && [ -e "$e/cache/rg.tar.gz" ]'
: > "$e/log"; correr
caso "ya bajado: no vuelve a llamar a curl"  '[ ! -s "$e/log" ]'
caso "ya bajado: el binario queda listo (OK)"  'linea OK "rg" >/dev/null'

# 5. ESTATICOS_REPETIR=N: cada caso corre N veces seguidas (para las caídas intermitentes) y falla si una falla
entorno; cp "$e/paq/rg.tar.gz" "$e/fuente"
printf '#!/bin/sh\necho corrio >> %s/ejecutado\nif [ "$1" = -o ]; then . /etc/os-release; echo "ID=$ID"; else echo instalado; fi\n' "$e" > "$e/paq/rg"; tar -czf "$e/paq/rg.tar.gz" -C "$e/paq" rg
cp "$e/paq/rg.tar.gz" "$e/fuente"; printf 'rg https://bajadas.test/rg.tar.gz %s rg\n' "$(sha256sum "$e/paq/rg.tar.gz" | cut -d' ' -f1)" > "$e/tabla"
correr ESTATICOS_REPETIR=3
caso "repetir 3: los dos casos de rg corren 3 veces cada uno"  '[ "$(wc -l < "$e/ejecutado")" -eq 6 ] && [ "$rc" -eq 0 ]'

# 4. herramientas que faltan en la instancia (git, script): se instalan con el gestor de paquetes
entorno; falso pacman 'echo "$*" >> '"$e"'/log; case $3 in util-linux) cp /usr/bin/true '"$e"'/bin/script;; git) cp /usr/bin/true '"$e"'/bin/git;; esac'; falso sudo '[ "$1" = -n ] && shift; exec "$@"'
cp "$e/paq/rg.tar.gz" "$e/fuente"; printf 'lazygit https://bajadas.test/rg.tar.gz %s rg\n' "$(sha256sum "$e/paq/rg.tar.gz" | cut -d' ' -f1)" > "$e/tabla"
correr ESTATICOS_SOLO=lazygit
caso "sin git ni script: los instala con pacman"  'grep -q -- "-S --noconfirm git" "$e/log" && grep -q -- "-S --noconfirm util-linux" "$e/log"'
entorno; falso sudo '[ "$1" = -n ] && shift; exec "$@"'; falso pacman 'exit 1'; falso script 'exit 0'
printf 'lazygit https://bajadas.test/rg.tar.gz %s rg\n' "$(sha256sum "$e/paq/rg.tar.gz" | cut -d' ' -f1)" > "$e/tabla"; cp "$e/paq/rg.tar.gz" "$e/fuente"
correr ESTATICOS_SOLO=lazygit
caso "git que no se puede instalar: SALTA que lo nombra y fallas: 0"  'linea SALTA "git" >/dev/null && grep -q "^fallas: 0" "$e/out"'

echo "fallas: $fallas"
[ "$fallas" -eq 0 ]
