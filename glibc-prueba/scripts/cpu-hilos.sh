#!/bin/bash
# Uso por SSH: ssh -p 8022 user@127.0.0.1 'cat > /tmp/cpu-hilos.sh' < scripts/cpu-hilos.sh; ssh ... 'bash /tmp/cpu-hilos.sh 20'
# CPU por hilo en un intervalo: Steam, Xwayland, sway
T=${1:-20}
pids="$(pgrep -f steamwebhelper) $(pgrep -x steam) $(pgrep -x Xwayland) $(pgrep -x sway)"
snap() { for p in $pids; do for t in /proc/$p/task/*; do
  [ -r $t/stat ] || continue
  read -r line < $t/stat; rest=${line##*) }; set -- $rest
  name=$(cat $t/comm 2>/dev/null)
  echo "$p/${t##*/} $(( ${12} + ${13} )) $name"
done; done; }
snap > /tmp/a.txt; sleep $T; snap > /tmp/b.txt
hz=$(getconf CLK_TCK)
join <(sort /tmp/a.txt) <(sort /tmp/b.txt) | awk -v T=$T -v hz=$hz '{d=$4-$2; if(d>0) printf "%6.1f%%  %s %s\n", d*100/hz/T, $1, $3}' | sort -rn | head -25
