#!/bin/bash
# Busca syscalls con rutas hechas fuera de __android_path_syscall (por función).
cd "$(dirname "$0")"
docker run --rm -v "$PWD/salida:/s:ro" glibc-cross bash -c '
NRS="49 51 45 43 89 5 6 8 9 11 12 14 15 56 437 48 439 79 291 34 33 35 53 452 54 88 27 264 37 38 276 36 78 17 200 203 221 281"
for f in /s/usr/lib/libc.so.6 /s/usr/lib/ld-linux-aarch64.so.1; do
  echo "== $f"
  aarch64-linux-gnu-objdump -d --no-show-raw-insn $f | awk -v nrs="$NRS" "
    BEGIN { split(nrs, a, \" \"); for (i in a) want[a[i]] = 1 }
    /^[0-9a-f]+ <.*>:\$/ { fn = \$2; x8 = -1 }
    /mov\tx8, #/ { v = \$NF; sub(/#/, \"\", v); x8 = (v ~ /^0x/) ? strtonum(v) : v + 0 }
    /svc\t#0x0/ { if (x8 in want) bad[fn \" nr=\" x8]++; x8 = -1 }
    END { for (k in bad) print \"  \" k }" | sort
done'
