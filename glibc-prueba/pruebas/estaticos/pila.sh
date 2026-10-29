#!/usr/bin/bash
# B17 (pruebas 15 y 16): pila de señales de un estático sin TLS (como Go). Corre DENTRO de la instancia con pila-arm64 en
# ${PILA:-/tmp/pila-arm64}; desde el PC usa pila-en-telefono.sh, que lo sube. Una línea por prueba; sale con 0 sin fallas.
PILA=${PILA:-/tmp/pila-arm64}; fallas=0
for modo in "un hilo:" "varios hilos:hilos"; do
  nombre=${modo%%:*}; arg=${modo#*:}
  if salida=$(timeout 60 "$PILA" $arg 2>&1); then echo "OK    pila de señales: $nombre"
  else echo "FALLA pila de señales: $nombre ($salida)"; fallas=$((fallas + 1)); fi
done
BSS=${BSS:-/tmp/bss-arm64}
if salida=$(timeout 20 "$BSS" 2>&1); then echo "OK    ELF con un segmento solo-.bss"
else echo "FALLA ELF con un segmento solo-.bss (código $?)"; fallas=$((fallas + 1)); fi
echo "fallas: $fallas"
[ "$fallas" -eq 0 ]
