G=$APP_FILES/glibc; L=$G/usr/lib; T=$NATIVE_DIR/libtracer.so; LD=$NATIVE_DIR/libld.so
R="$LD --library-path $L"
echo "== contexto: $(cat /proc/self/attr/current)"
echo "== E: bash via cargador en nativeLibraryDir, sin rastreador"
$R $G/usr/bin/bash -c 'echo "  ok bash $BASH_VERSION"' 2>&1; echo "  exit=$?"
echo "== F: igual, con rastreador + bateria de comandos"
$T $LD --library-path $L $G/usr/bin/bash -c "
  echo \"  bash \$BASH_VERSION, pid \$\$\"
  $R $G/usr/bin/ls --version | head -1
  echo \"  nproc: \$($R $G/usr/bin/nproc)\"
  printf 'c\nb\na\n' | $R $G/usr/bin/sort --parallel=4 | tr '\n' ' '; echo
  $R $G/usr/bin/stat -c '  stat: %n %s bytes' $L/libc.so.6
  echo hola > \$APP_FILES/t1 && $R $G/usr/bin/cp \$APP_FILES/t1 \$APP_FILES/t2 && echo \"  cp: \$($R $G/usr/bin/cat \$APP_FILES/t2)\"
  echo \"  mktemp: \$($R $G/usr/bin/mktemp -p \$APP_FILES)\"
  echo \"  date: \$($R $G/usr/bin/date -u +%FT%T)\"
  $R $G/usr/bin/sleep 0.2 && echo '  sleep ok'
  $R $G/usr/bin/timeout 1 $R $G/usr/bin/sleep 5; echo \"  timeout exit=\$?\"
  $R $G/usr/bin/id
" 2>&1; echo "  exit=$?"
rm -f $APP_FILES/t1 $APP_FILES/t2 $APP_FILES/tmp.*
