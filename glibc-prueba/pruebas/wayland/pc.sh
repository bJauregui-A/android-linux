#!/usr/bin/bash
# B94: el anfitrión Wayland reconoce los clientes de una instancia con el mismo criterio que Pausa.deLaInstancia.
# Corre en el PC, compila app/src/main/cpp/instancia.c con cc:  pruebas/wayland/pc.sh
cd "$(dirname "$0")/../.." || exit 1
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# de <cwd> <cmdline> <raiz>: sale 0 si es de la instancia; "-" es NULL.
cat > "$tmp/main.c" <<'EOF'
#include <string.h>
#include "instancia.h"
static const char *arg (const char *s) { return strcmp (s, "-") == 0 ? NULL : s; }
int main (int argc, char **argv) { return de_la_instancia (arg (argv[1]), arg (argv[2]), argv[3]) ? 0 : 1; }
EOF
cc -Wall -Werror -I app/src/main/cpp -o "$tmp/de" "$tmp/main.c" app/src/main/cpp/instancia.c ||
  { echo "FALLA no compila instancia.c"; echo "fallas: 1"; exit 1; }
de() { "$tmp/de" "$@"; }
R=/data/user/0/app/files/instancias/a

caso "cwd dentro de la raíz"           'de "$R/home/user" "" "$R"'
caso "cwd igual a la raíz"             'de "$R" "" "$R"'
caso "raíz en cmdline seguida de /"    'de "/" "/ld.so $R/usr/bin/sway -d" "$R"'
caso "raíz en cmdline seguida de espacio"  'de "/" "/ld.so --root $R sway" "$R"'
caso "raíz al final de cmdline"        'de "/" "/ld.so --root $R" "$R"'
caso "otra instancia que empieza igual, en cwd"      '! de "${R}b/home" "" "$R"'
caso "otra instancia que empieza igual, en cmdline"  '! de "/" "/ld.so ${R}b/usr/bin/sway ${R}b" "$R"'
caso "cwd y cmdline vacíos"            '! de "" "" "$R"'
caso "cwd y cmdline NULL"              '! de - - "$R"'

echo "fallas: $fallas"
[ "$fallas" -eq 0 ]
