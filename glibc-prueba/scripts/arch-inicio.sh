# Primer arranque del prefijo files/archlinux (lo corre la app; ver instalar-arch.sh)
P=$APP_FILES/archlinux; L=$NATIVE_DIR/libldp.so
U=$(id -u); G=$(id -g)
grep -q "^user:" $P/etc/passwd || echo "user:x:$U:$G:Usuario:/home/user:/bin/bash" >> $P/etc/passwd
grep -q "^user:" $P/etc/group || echo "user:x:$G:" >> $P/etc/group
echo "== arch-inicio: scripts post_install (fakeroot)"
GLIBC_DEBUG_SIGSYS=${DEBUG:-0} GLIBC_PREFIX=$P GLIBC_LOADER=$L GLIBC_FAKEROOT=1 HOME=/root PATH=/usr/bin LANG=C.UTF-8 TERM=dumb \
$L /usr/bin/bash -c '
  for d in /var/lib/pacman/local/*/; do
    [ -f $d/install ] || continue
    ver=$(sed -n "/^%VERSION%/{n;p}" $d/desc); n=$(basename $d)
    out=$(cd / && bash -c ". $d/install; declare -F post_install >/dev/null && post_install $ver" 2>&1); r=$?
    echo "  ${n}: exit=$r $(echo "$out" | head -3 | tr "\n" "|")"
  done
  echo "== pacman-key"
  pacman-key --init 2>&1 | tail -3 | sed "s/^/  /"
  pacman-key --populate archlinuxarm 2>&1 | tail -3 | sed "s/^/  /"
  echo "== pacman -Q: $(pacman -Q | wc -l) paquetes; $(pacman -Q pacman)"
' 2>&1; echo "  exit=$?"
