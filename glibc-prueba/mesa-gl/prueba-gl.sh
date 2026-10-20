#!/usr/bin/bash
# Prueba el GL de ~/mesa-gl (Zink bajo drisw, sin egl-zink) dentro de sway, por SSH.
# Uso: bash prueba-gl.sh [segundos]   (abre es2gears_wayland y glxgears unos segundos y los cierra)
S=${1:-8}
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-1}
export DISPLAY=${DISPLAY:-:1}
export VK_ICD_FILENAMES=$HOME/turnip-x11/share/vulkan/icd.d/freedreno_icd.aarch64.json
unset LD_PRELOAD LIBGL_ALWAYS_SOFTWARE
export LD_LIBRARY_PATH=$HOME/mesa-gl/lib GALLIUM_DRIVER=zink MESA_LOADER_DRIVER_OVERRIDE=zink
echo "--- eglinfo wayland"
eglinfo -B -p wayland 2>&1 | grep -iE "renderer|version string|error" | head -6
echo "--- es2gears_wayland ${S}s"
timeout $S es2gears_wayland 2>&1 | grep -iE "fps|error|fail" | tail -3
echo "--- glxgears ${S}s (X11)"
timeout $S glxgears 2>&1 | grep -iE "fps|error|fail" | tail -3
