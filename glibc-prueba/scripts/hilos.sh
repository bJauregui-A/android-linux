#!/bin/bash
# CPU por hilo de todos los procesos en T segundos (uso: bash hilos.sh [segundos] [líneas])
T=${1:-10}; S=$(mktemp -d); trap 'rm -rf "$S"' EXIT
snap() { for t in /proc/[0-9]*/task/*; do read -r line < $t/stat 2>/dev/null || continue; rest=${line##*) }; set -- $rest; p=${t#/proc/}; p=${p%%/*}; echo "$p/${t##*/} $(( ${12} + ${13} )) $(tr ' ' _ < $t/comm 2>/dev/null)"; done 2>/dev/null; }
snap | sort > $S/a; sleep $T; snap | sort > $S/b
hz=$(getconf CLK_TCK)
join $S/a $S/b | awk -v T=$T -v hz=$hz '{d=$4-$2; tot+=d; if(d>0) printf "%6.1f%%  %s %s\n", d*100/hz/T, $1, $3} END {printf "%6.1f%%  TOTAL (8 núcleos = 800%%)\n", tot*100/hz/T}' | sort -rn | head -${2:-25}
