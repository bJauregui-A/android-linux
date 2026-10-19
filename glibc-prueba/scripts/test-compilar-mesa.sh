# Corre ~/compilar-mesa.sh dentro de la app (incremental si ya existe ~/src/mesa-*/build).
P=$APP_FILES/archlinux; L=$NATIVE_DIR/libldp.so
GLIBC_PREFIX=$P GLIBC_LOADER=$L HOME=/home/user PATH=/usr/bin LANG=C.UTF-8 TERM=dumb \
$L /usr/bin/bash -c 'bash ~/compilar-mesa.sh 2>&1 | grep -E "FAILED|rror|warning: unused|^\[[0-9]+/|mesa listo|^real" | tail -25' 2>&1; echo "=== fin"
