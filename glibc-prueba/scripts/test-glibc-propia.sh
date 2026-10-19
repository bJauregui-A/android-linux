G=$APP_FILES/glibc; L=$G/usr/lib; GP=$APP_FILES/glibcp; LDP=$NATIVE_DIR/libldp.so
R="$LDP --library-path $GP:$L"
echo "== contexto: $(cat /proc/self/attr/current)"
echo "== H: glibc propia, SIN rastreador y SIN GLIBC_TUNABLES"
$R $G/usr/bin/bash -c "
  echo \"  bash \$BASH_VERSION, pid \$\$\"
  $R $G/usr/bin/ls --version | head -1
  echo \"  nproc: \$($R $G/usr/bin/nproc)\"
  printf 'c\nb\na\n' | $R $G/usr/bin/sort --parallel=4 | tr '\n' ' '; echo
  $R $G/usr/bin/stat -c '  stat: %n %s bytes' $GP/libc.so.6
  echo hola > \$APP_FILES/t1 && $R $G/usr/bin/cp \$APP_FILES/t1 \$APP_FILES/t2 && echo \"  cp: \$($R $G/usr/bin/cat \$APP_FILES/t2)\"
  echo \"  date: \$($R $G/usr/bin/date -u +%FT%T)\"
  $R $G/usr/bin/timeout 1 $R $G/usr/bin/sleep 5; echo \"  timeout exit=\$?\"
" 2>&1; echo "  exit=$?"
rm -f $APP_FILES/t1 $APP_FILES/t2
