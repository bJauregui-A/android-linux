# pacman dentro de la app: sincronizar e instalar un paquete (fakeroot)
P=$APP_FILES/archlinux; L=$NATIVE_DIR/libldp.so
GLIBC_DEBUG_SIGSYS=${DEBUG:-0} GLIBC_PREFIX=$P GLIBC_LOADER=$L GLIBC_FAKEROOT=1 HOME=/root PATH=/usr/bin LANG=C.UTF-8 TERM=dumb \
$L /usr/bin/bash -c '
  echo "== pacman -Sy"
  pacman -Sy --noconfirm 2>&1 | grep -v "syscall 439"
  echo "== pacman -S nano htop git"
  pacman -S --noconfirm nano htop git 2>&1 | grep -v "syscall 439"
  echo "== resultado"
  nano --version | head -1
  htop --version
  git --version; git -C /tmp init -q prueba && echo "  git init ok: $(ls /tmp/prueba/.git | wc -l) entradas"; rm -rf /tmp/prueba
  pacman -Qi nano | grep -E "^(Name|Version|Install Reason|Validated By)"
' 2>&1; echo "  exit=$?"
