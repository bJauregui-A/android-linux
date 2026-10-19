P=$APP_FILES/arch; LDP=$NATIVE_DIR/libldp.so
mkdir -p $P/home/user $P/tmp $P/etc $P/proc $P/sys $P/dev $P/data $P/system
for d in bin sbin lib; do [ -e $P/$d ] || ln -s usr/${d/sbin/bin} $P/$d; done
echo "user:x:$(id -u):$(id -g):Usuario:/home/user:/bin/bash" > $P/etc/passwd
echo "user:x:$(id -g):" > $P/etc/group
echo "== I: traducción de rutas (GLIBC_PREFIX=$P)"
GLIBC_PREFIX=$P GLIBC_LOADER=$LDP PATH=/usr/bin HOME=/home/user TMPDIR=/tmp $LDP /usr/bin/bash -c '
  echo "  bash $BASH_VERSION"
  echo "  ls /: $(ls / | tr "\n" " ")"
  echo "  id: $(id)"
  echo "  whoami: $(whoami)"
  echo "  /usr/bin tiene $(ls /usr/bin | wc -l) programas"
  echo "  ls por PATH: $(ls --version | head -1)"
  cd /usr/lib && echo "  pwd: $(pwd)  /bin/pwd: $(/bin/pwd)"
  cd ~ && echo "  cd ~: $(pwd)"
  echo "  readlink -f /bin/sh: $(readlink -f /bin/sh)"
  printf "#!/usr/bin/bash\necho \"  script: \$0 \$1\"\n" > /tmp/s.sh && chmod +x /tmp/s.sh && /tmp/s.sh hola
  printf "#!/usr/bin/env bash\necho \"  env script: \$BASH_VERSION\"\n" > /tmp/e.sh && chmod +x /tmp/e.sh && /tmp/e.sh
  ln -sf /usr/bin/date /tmp/fecha && echo "  symlink: $(readlink /tmp/fecha) -> $(/tmp/fecha -u +%F)"
  mkdir -p /tmp/a/b && mv /tmp/a /tmp/c && echo "  mkdir/mv: $(ls -d /tmp/c/b)" && rm -r /tmp/c
  echo "  env -i: $(env -i /usr/bin/bash -c "ls /etc | tr \"\n\" \" \"")"
  echo "  comm de cat: $(cat /proc/self/comm)"
  echo "  bionic: $(/system/bin/toybox echo toybox ok)"
  printf "c\nb\na\n" | sort --parallel=4 | tr "\n" " "; echo
  timeout 1 sleep 5; echo "  timeout exit=$?"
  echo "  $(ls /no/existe 2>&1)"
  echo "  $(nocomando 2>&1)"
' 2>&1; echo "  exit=$?"
rm -f $P/tmp/s.sh $P/tmp/e.sh $P/tmp/fecha
