G=$APP_FILES/glibc; L=$G/usr/lib; T=$NATIVE_DIR/libtracer.so; LD=$NATIVE_DIR/libld.so
export GLIBC_TUNABLES=glibc.pthread.rseq=0
echo "== G: con rseq desactivado por tunable"
$T $LD --library-path $L $G/usr/bin/bash -c "echo \"  bash \$BASH_VERSION\"; printf 'b\na\n' | $LD --library-path $L $G/usr/bin/sort --parallel=4 | tr '\n' ' '; echo" 2>&1; echo "  exit=$?"
