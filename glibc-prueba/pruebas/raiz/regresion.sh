#!/bin/bash
# Regresión de B26: mismos comandos con la libc instalada y con la nueva, en la
# misma instancia y contexto. Correr con scripts/probar-en-telefono.sh <instancia> regresion.sh
D=/data/user/0/dev.ben4shot.glibcprueba.sdk36/files/prueba-libc
f=0
pasos() {  # $1 = etiqueta
  printf '#!/bin/sh\necho shebang-ok\n' > /tmp/rz-sb.sh; chmod +x /tmp/rz-sb.sh
  [ "$(/tmp/rz-sb.sh)" = shebang-ok ] && echo "OK    $1 #! script" || { echo "FALLA $1 #! script"; f=1; }
  [ "$(bash -c 'echo $((1+1))')" = 2 ] && echo "OK    $1 bash -c" || { echo "FALLA $1 bash -c"; f=1; }
  if command -v zsh >/dev/null; then [ "$(zsh -c 'echo z')" = z ] && echo "OK    $1 zsh -c" || { echo "FALLA $1 zsh"; f=1; }; fi
  if command -v pacman >/dev/null; then
    pacman -Qk pacman 2>&1 | tail -1 | sed "s/^/OK    $1 /"
  fi
  if command -v apt-get >/dev/null; then
    r=$(apt-get update 2>&1 | tail -2); echo "$r" | grep -qiE "^(E:|Err)" && { echo "FALLA $1 apt-get update: $r"; f=1; } || echo "OK    $1 apt-get update"
  fi
  if command -v sudo >/dev/null; then sudo -n true 2>/dev/null && echo "OK    $1 sudo" || echo "AVISO $1 sudo -n falló (puede ser normal)"; fi
  rm -f /tmp/rz-sb.sh
}
tiempo() {  # $1 = etiqueta: 3 veces find sobre una carpeta grande
  local t=""
  for i in 1 2 3; do s=$(date +%s%N); find /usr >/dev/null 2>&1; e=$(date +%s%N); t="$t $(( (e - s) / 1000000 ))ms"; done
  echo "TIEMPO $1 find /usr ($(find /usr 2>/dev/null | wc -l) entradas):$t"
}
echo "== instancia: $(basename "$GLIBC_PREFIX")"
pasos instalada; tiempo instalada
export LD_LIBRARY_PATH=$D${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
pasos nueva; tiempo nueva
exit $f
