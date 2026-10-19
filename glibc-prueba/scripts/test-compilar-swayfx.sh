# Corre ~/compilar-swayfx.sh dentro de la app (incremental si ya existe ~/src/swayfx-*/build).
P=$APP_FILES/archlinux; L=$NATIVE_DIR/libldp.so
GLIBC_PREFIX=$P GLIBC_LOADER=$L HOME=/home/user PATH=/usr/bin LANG=C.UTF-8 TERM=dumb \
$L /usr/bin/bash -c 'bash ~/compilar-swayfx.sh > ~/swayfx.log 2>&1; echo "salida $?"
  grep -E "FAILED|rror:|ERROR|Dependency .* found: NO|swayfx listo|^real" ~/swayfx.log | grep -v "found: YES" | sed s/error/ERR/g | tail -40' 2>&1; echo "=== fin"
