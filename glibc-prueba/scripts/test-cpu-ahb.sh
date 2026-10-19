# CPU del proceso de la app y del cliente: cero copias (android-ahb-v1) contra
# dmabuf leído por CPU (MESA_WSI_AHB=0); vkcube y es2gears_wayland (Zink), 12 s cada uno.
# Uso: ESPERA=40 TIEMPO=150 scripts/correr-wl.sh scripts/test-cpu-ahb.sh /tmp/c.png
P=$APP_FILES/archlinux; L=$NATIVE_DIR/libldp.so
export APP=$PPID
GLIBC_PREFIX=$P GLIBC_LOADER=$L HOME=/home/user PATH=/usr/bin LANG=C.UTF-8 TERM=dumb \
$L /usr/bin/bash -c '
  export VK_ICD_FILENAMES=$HOME/turnip/share/vulkan/icd.d/freedreno_icd.aarch64.json
  export XDG_RUNTIME_DIR=/run/user/$(id -u) WAYLAND_DISPLAY=wayland-0
  export MESA_LOADER_DRIVER_OVERRIDE=zink LD_PRELOAD=$HOME/turnip/lib/libegl-zink.so
  tics() { awk "{print \$14+\$15}" /proc/$APP/stat; }
  for prog in "vkcube --wsi wayland" es2gears_wayland; do
    for modo in dmabuf ahb; do
      if [ $modo = dmabuf ]; then export MESA_WSI_AHB=0; else unset MESA_WSI_AHB; fi
      a=$(tics); TIMEFORMAT="%U+%S"
      t=$( { time timeout 12 $prog > /tmp/salida.txt 2>&1; } 2>&1 ); b=$(tics)
      echo "$prog [$modo]: app $(( (b-a) ))0 ms de CPU, cliente user+sys ${t} s"
      grep -iE "frames in|error|MESA|fallo" /tmp/salida.txt | tail -3
    done
  done
  sleep 1; timeout 30 vkcube --wsi wayland > /dev/null 2>&1 &
' 2>&1; echo "=== fin"
