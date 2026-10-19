# Corre ~/compilar-wlroots.sh dentro de la app (incremental si ya existe ~/src/wlroots-*/build).
P=$APP_FILES/archlinux; L=$NATIVE_DIR/libldp.so
GLIBC_PREFIX=$P GLIBC_LOADER=$L HOME=/home/user PATH=/usr/bin LANG=C.UTF-8 TERM=dumb \
$L /usr/bin/bash -c 'bash ~/compilar-wlroots.sh > ~/wlroots.log 2>&1; echo "salida $?"
  grep -E "FAILED|rror:|ERROR|Dependency .* found: NO|Run-time dependency|símbolos|faltan|^[a-z_]+$|wlroots listo|^real" ~/wlroots.log | grep -v "found: YES" | tail -40' 2>&1; echo "=== fin"
