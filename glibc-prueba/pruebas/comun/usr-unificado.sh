# Ayudante común (se carga con `.`): comprobación del /usr unificado de la base de una distro.
#   usr_unificado <lista> <enlace>:<destino>...
# <lista> es la salida de `tar -tvf` de la base. Para cada par, <enlace> existe como enlace relativo a <destino> y
# ningún miembro queda debajo (<enlace>/x sería una carpeta real). Cada distro lo llama desde su base.sh con su forma.
usr_unificado() {
  local lista=$1 par enlace destino ok=0
  shift
  # nombres de los miembros, sin la ficha de tar, sin " -> destino" y sin "./" al frente
  local nombres; nombres=$(sed -E 's/^[^ ]+ [^ ]+ +[0-9]+ [0-9-]+ [0-9:]+ //; s/ -> .*$//; s#^\./##' "$lista")
  for par in "$@"; do
    enlace=${par%%:*}; destino=${par#*:}
    grep -qE "^l[^ ]+ .* (\./)?$enlace -> $destino$" "$lista" || { echo "  $enlace no es un enlace a $destino" >&2; ok=1; }
    if grep -q "^$enlace/" <<<"$nombres"; then echo "  hay miembros debajo de $enlace/" >&2; ok=1; fi
  done
  return $ok
}
