#!/bin/bash
# B17: compila pila.c, le adjunta el binario a pila.sh y lo corre en una instancia (probar-en-telefono.sh).
#   pruebas/estaticos/pila-en-telefono.sh <instancia> [limite-seg]
cd "$(dirname "$0")" || exit 1
inst=$1; [ -n "$inst" ] || { echo "uso: $0 <instancia> [limite]" >&2; exit 2; }
./compilar-pila.sh || exit 2
tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
{ echo "base64 -d > /tmp/pila-arm64 <<'B64'"; base64 pila-arm64; echo B64; echo "chmod +x /tmp/pila-arm64"; echo "base64 -d > /tmp/bss-arm64 <<'B64'"; base64 bss-arm64; echo B64; echo "chmod +x /tmp/bss-arm64"; cat pila.sh; } > "$tmp"
../../scripts/probar-en-telefono.sh "$inst" "$tmp" "${2:-120}"
