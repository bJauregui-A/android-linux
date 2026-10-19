# Mide un compositor anidado en el anfitrión: RAM (RSS/PSS) y CPU en reposo y con vkcube.
# El compositor se elige con WM (sway | swayfx | swayfx-plano | hyprland), que el script de abajo
# reemplaza al subirlo (sed). Mide 10 s en cada caso: app (anfitrión), compositor, vkcube.
# Uso: ESPERA=60 TIEMPO=120 scripts/correr-wl.sh <(sed s/@WM@/sway/ scripts/test-medir-wm.sh) x.png
P=$APP_FILES/archlinux; L=$NATIVE_DIR/libldp.so
export APP=$PPID WM=@WM@
GLIBC_PREFIX=$P GLIBC_LOADER=$L HOME=/home/user PATH=/usr/bin LANG=C.UTF-8 TERM=dumb \
$L /usr/bin/bash -c '
  export XDG_RUNTIME_DIR=/run/user/$(id -u) WAYLAND_DISPLAY=wayland-0
  export VK_ICD_FILENAMES=$HOME/turnip/share/vulkan/icd.d/freedreno_icd.aarch64.json
  export WLR_NO_HARDWARE_CURSORS=1
  tics() { awk "{print \$14+\$15}" /proc/$1/stat 2>/dev/null || echo 0; }
  mem() { awk "/^Rss:/{r=\$2} /^Pss:/{p=\$2} END{printf \"RSS %d MB, PSS %d MB\", r/1024, p/1024}" /proc/$1/smaps_rollup 2>/dev/null; }
  pkill -x sway; pkill -x Hyprland; sleep 1
  case $WM in
    sway)   WLR_RENDERER=vulkan LD_LIBRARY_PATH=$HOME/wlroots/lib sway > /tmp/wm-$WM.log 2>&1 & ;;
    # swayfx: renderer GLES de scenefx por Zink (EGL "software" = Zink sobre Turnip)
    swayfx|swayfx-plano)
      c=~/.config/swayfx/config; [ $WM = swayfx-plano ] && c=~/.config/sway/config
      WLR_RENDERER_FORCE_SOFTWARE=1 GALLIUM_DRIVER=zink LD_LIBRARY_PATH=$HOME/wlroots/lib \
        $HOME/swayfx/bin/sway -c $c > /tmp/wm-$WM.log 2>&1 & ;;
    hyprland) Hyprland > /tmp/wm-$WM.log 2>&1 & ;;
  esac
  wm=$!
  sleep 8
  if ! kill -0 $wm 2>/dev/null; then echo "$WM no arrancó:"; tail -25 /tmp/wm-$WM.log | sed s/error/ERR/g; exit; fi
  wm=$!
  echo "$WM en reposo: $(mem $wm)"
  a1=$(tics $APP); s1=$(tics $wm); sleep 10; a2=$(tics $APP); s2=$(tics $wm)
  echo "$WM en reposo (10 s): app $(( (a2-a1)*10 )) ms, $WM $(( (s2-s1)*10 )) ms"
  export WAYLAND_DISPLAY=$(basename $(ls -t $XDG_RUNTIME_DIR/wayland-[1-9] | head -1))
  vkcube --wsi wayland > /tmp/vkcube-$WM.log 2>&1 & vk=$!
  sleep 4
  a1=$(tics $APP); s1=$(tics $wm); v1=$(tics $vk); sleep 10
  a2=$(tics $APP); s2=$(tics $wm); v2=$(tics $vk)
  echo "$WM con vkcube (10 s): app $(( (a2-a1)*10 )) ms, $WM $(( (s2-s1)*10 )) ms, vkcube $(( (v2-v1)*10 )) ms, total $(( (a2-a1+s2-s1+v2-v1)*10 )) ms"
  echo "$WM con vkcube: $(mem $wm)"
  (sleep 20; kill $vk) >/dev/null 2>&1 &
' 2>&1; echo "=== fin"
