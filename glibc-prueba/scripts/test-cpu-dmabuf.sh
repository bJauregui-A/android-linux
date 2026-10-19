# CPU del anfitrión y de vkcube, dmabuf contra MESA_VK_WSI_DEBUG=sw (15 s cada uno).
# Uso: ESPERA=8 TIEMPO=150 scripts/correr-wl.sh scripts/test-cpu-dmabuf.sh /tmp/c.png
P=$APP_FILES/archlinux; L=$NATIVE_DIR/libldp.so
export APP=$PPID
GLIBC_PREFIX=$P GLIBC_LOADER=$L HOME=/home/user PATH=/usr/bin LANG=C.UTF-8 TERM=dumb \
$L /usr/bin/bash -c '
  export VK_ICD_FILENAMES=$HOME/turnip/share/vulkan/icd.d/freedreno_icd.aarch64.json
  export XDG_RUNTIME_DIR=/run/user/$(id -u) WAYLAND_DISPLAY=wayland-0
  tics() { awk "{print \$14+\$15}" /proc/$APP/stat; }
  for modo in dmabuf sw dmabuf sw; do
    if [ $modo = sw ]; then export MESA_VK_WSI_DEBUG=sw; else unset MESA_VK_WSI_DEBUG; fi
    a=$(tics); TIMEFORMAT="%U+%S"; t=$( { time timeout 15 vkcube --wsi wayland >/dev/null 2>&1; } 2>&1 ); b=$(tics)
    echo "$modo: anfitrión $(( (b-a) ))0 ms de CPU, vkcube user+sys ${t} s (15 s de cubo)"
  done
' 2>&1; echo "=== fin"
