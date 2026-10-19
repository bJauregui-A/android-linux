# sway con el renderer Vulkan de wlroots (wlroots/parches) y buffers android-ahb-v1.
# Reemplaza el sway del servicio; abre foot y vkcube dentro. Mide CPU de la app.
# Uso: ESPERA=40 TIEMPO=90 scripts/correr-wl.sh scripts/test-sway-vulkan.sh /tmp/s.png
P=$APP_FILES/archlinux; L=$NATIVE_DIR/libldp.so
export APP=$PPID
GLIBC_PREFIX=$P GLIBC_LOADER=$L HOME=/home/user PATH=/usr/bin LANG=C.UTF-8 TERM=dumb \
$L /usr/bin/bash -c '
  export XDG_RUNTIME_DIR=/run/user/$(id -u) WAYLAND_DISPLAY=wayland-0
  export VK_ICD_FILENAMES=$HOME/turnip/share/vulkan/icd.d/freedreno_icd.aarch64.json
  export WLR_NO_HARDWARE_CURSORS=1 WLR_RENDERER=${RENDERER:-vulkan}
  pkill -x sway; sleep 1
  LD_LIBRARY_PATH=$HOME/wlroots/lib sway -d > /tmp/sway-vk.log 2>&1 &
  sleep 6
  grep -iE "renderer|vulkan|allocator|ahb|Found matching|DRM|error|fail" /tmp/sway-vk.log | grep -v "^.*DEBUG.*extension" | head -30
  S=$(ls -t $XDG_RUNTIME_DIR/wayland-[1-9] 2>/dev/null | head -1); echo "socket de sway: $S"
  export WAYLAND_DISPLAY=$(basename "$S")
  foot > /tmp/foot.log 2>&1 &
  sleep 3; timeout 15 vkcube --wsi wayland > /tmp/vkcube.log 2>&1 &
  tics() { awk "{print \$14+\$15}" /proc/$APP/stat; }
  sleep 3; a=$(tics); sleep 10; b=$(tics); echo "app: $(( b-a ))0 ms de CPU en 10 s"
  pgrep -x sway >/dev/null && echo "sway vivo" || { echo "sway murió"; tail -20 /tmp/sway-vk.log; }
  tail -3 /tmp/vkcube.log
' 2>&1; echo "=== fin"
