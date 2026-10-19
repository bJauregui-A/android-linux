# CPU del escritorio con vkcube dentro de sway: hoy (pixman + cliente por shm,
# MESA_VK_WSI_DEBUG=sw) contra GPU (wlroots parchado: Vulkan + android-ahb-v1 + dmabuf).
# Mide 10 s: proceso de la app (anfitrión), sway y vkcube por separado.
# Uso: ESPERA=80 TIEMPO=120 scripts/correr-wl.sh scripts/test-cpu-sway.sh /tmp/c.png
P=$APP_FILES/archlinux; L=$NATIVE_DIR/libldp.so
export APP=$PPID
GLIBC_PREFIX=$P GLIBC_LOADER=$L HOME=/home/user PATH=/usr/bin LANG=C.UTF-8 TERM=dumb \
$L /usr/bin/bash -c '
  export XDG_RUNTIME_DIR=/run/user/$(id -u) WAYLAND_DISPLAY=wayland-0
  export VK_ICD_FILENAMES=$HOME/turnip/share/vulkan/icd.d/freedreno_icd.aarch64.json
  export WLR_NO_HARDWARE_CURSORS=1
  tics() { awk "{print \$14+\$15}" /proc/$1/stat 2>/dev/null || echo 0; }
  for modo in pixman vulkan; do
    pkill -x sway; sleep 1
    if [ $modo = pixman ]; then
      WLR_RENDERER=pixman sway > /tmp/sway-$modo.log 2>&1 &
    else
      WLR_RENDERER=vulkan LD_LIBRARY_PATH=$HOME/wlroots/lib sway > /tmp/sway-$modo.log 2>&1 &
    fi
    sleep 5
    sway_pid=$(pgrep -x sway)
    export WAYLAND_DISPLAY=$(basename $(ls -t $XDG_RUNTIME_DIR/wayland-[1-9] | head -1))
    if [ $modo = pixman ]; then export MESA_VK_WSI_DEBUG=sw; else unset MESA_VK_WSI_DEBUG; fi
    vkcube --wsi wayland > /tmp/vkcube-$modo.log 2>&1 & vk=$!
    sleep 4
    a1=$(tics $APP); s1=$(tics $sway_pid); v1=$(tics $vk)
    sleep 10
    a2=$(tics $APP); s2=$(tics $sway_pid); v2=$(tics $vk)
    kill $vk 2>/dev/null
    echo "$modo: app $(( (a2-a1)*10 )) ms, sway $(( (s2-s1)*10 )) ms, vkcube $(( (v2-v1)*10 )) ms (en 10 s), total $(( (a2-a1+s2-s1+v2-v1)*10 )) ms"
    export WAYLAND_DISPLAY=wayland-0
  done
  # queda sway por GPU con vkcube para la captura
  WAYLAND_DISPLAY=$(basename $(ls -t $XDG_RUNTIME_DIR/wayland-[1-9] | head -1)) timeout 20 vkcube --wsi wayland >/dev/null 2>&1 &
' 2>&1; echo "=== fin"
