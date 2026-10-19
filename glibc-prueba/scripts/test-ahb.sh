# Cero copias (android-ahb-v1): compila turnip/prueba-ahb.c dentro de la app y lo
# corre conectado directo al anfitrión; mide la CPU del proceso de la app.
# Uso: scripts/subir-ahb.sh && ESPERA=8 TIEMPO=120 scripts/correr-wl.sh scripts/test-ahb.sh /tmp/c.png
P=$APP_FILES/archlinux; L=$NATIVE_DIR/libldp.so
export APP=$PPID
GLIBC_PREFIX=$P GLIBC_LOADER=$L HOME=/home/user PATH=/usr/bin LANG=C.UTF-8 TERM=dumb \
$L /usr/bin/bash -c '
  export VK_ICD_FILENAMES=$HOME/turnip/share/vulkan/icd.d/freedreno_icd.aarch64.json
  export XDG_RUNTIME_DIR=/run/user/$(id -u) WAYLAND_DISPLAY=wayland-0
  FORMATO=bgra; cd ~/src/ahb || exit 1
  gcc -O2 -o prueba-ahb prueba-ahb.c xdg-shell-protocol.c android-ahb-v1-protocol.c \
      -lwayland-client -lvulkan -lm || exit 1
  tics() { awk "{print \$14+\$15}" /proc/$APP/stat; }
  a=$(tics); ./prueba-ahb ${SEGUNDOS:-10} $FORMATO; b=$(tics)
  echo "anfitrión (todo el proceso de la app): $(( (b-a) ))0 ms de CPU"
' 2>&1; echo "=== fin"
