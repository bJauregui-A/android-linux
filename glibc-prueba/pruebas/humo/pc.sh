#!/usr/bin/bash
# B16: la batería de humo (humo.sh) detecta fallas y saltos. Corre en el PC con comandos falsos en el PATH:
#   pruebas/humo/pc.sh
cd "$(dirname "$0")/../.." || exit 1
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
HUMO=$PWD/pruebas/humo/humo.sh

# Entorno nuevo: bin/ solo con las herramientas básicas (sin pacman ni apt-get del PC) y los falsos que cada caso agrega.
entorno() {
  e=$(mktemp -d -p "$tmp"); mkdir "$e/bin"; : > "$e/log"
  for c in bash env timeout grep cat mktemp rm sleep sed date mkdir touch wc tee head tr ls chmod printf stdbuf python3 pgrep readlink; do
    ln -s "$(command -v "$c")" "$e/bin/$c"
  done
  falso sudo 'if [ "$1" = -n ] && [ "$2" = true ]; then exit 0; fi; [ "$1" = -n ] && shift; exec "$@"'
}
falso() { printf '#!/bin/sh\n%s\n' "$2" > "$e/bin/$1"; chmod +x "$e/bin/$1"; }
# pacman falso: anota los argumentos; con $e/falla-una-vez la primera instalación dice "target not found".
pacman_bueno() {
  falso pacman 'echo "$*" >> '"$e"'/log
if [ "$1" = -S ] && [ -e '"$e"'/falla-una-vez ]; then rm '"$e"'/falla-una-vez; echo "error: target not found: tree" >&2; exit 1; fi
exit 0'
}
# correr <grupo> [VAR=valor...]: entorno limpio (sin el DISPLAY del PC); salida en $e/out, código en $rc
correr() {
  g=$1; shift
  /usr/bin/env -i PATH="$e/bin" HUMO_SOLO="$g" HUMO_X11_DIR="$e/x11" HUMO_GPU_SEGUNDOS=3 ${HUMO_CLAVE:+HUMO_CLAVE="$HUMO_CLAVE"} "$@" \
    /usr/bin/bash "$HUMO" > "$e/out" 2>&1; rc=$?
}
linea() { grep -E "^$1 +.*$2" "$e/out"; }

# 1. sudo que pide contraseña
entorno; pacman_bueno; falso sudo 'exit 1'; correr shell
caso "sudo sin contraseña: la línea de sudo es FALLA"  'linea FALLA "sudo" >/dev/null'
caso "sudo sin contraseña: humo.sh sale distinto de 0"  '[ "$rc" -ne 0 ]'

# 2. pacman que instala y quita bien
entorno; pacman_bueno; correr shell
caso "pacman bueno: las líneas de paquetes son OK"  'linea OK "instala" >/dev/null && linea OK "quita" >/dev/null'
caso "pacman bueno: humo.sh sale con 0"  '[ "$rc" -eq 0 ]'
caso "pacman bueno: no actualiza el índice"  '! grep -q -- "-Sy" "$e/log"'

# 3. índice viejo: -Sy una sola vez y se reintenta
entorno; pacman_bueno; touch "$e/falla-una-vez"; correr shell
caso "índice viejo: se actualiza una sola vez"  '[ "$(grep -c -- "-Sy" "$e/log")" -eq 1 ]'
caso "índice viejo: la instalación queda OK"  'linea OK "instala" >/dev/null && [ "$rc" -eq 0 ]'

# 4. apt-get sin pacman
entorno; falso apt-get 'echo "apt-get $*" >> '"$e"'/log; exit 0'; correr shell
caso "apt-get: se usa apt-get y no pacman"  'grep -q "^apt-get install -y tree" "$e/log" && [ "$rc" -eq 0 ]'

# 5. tree ya instalado: no se quita
entorno; pacman_bueno; falso tree 'exit 0'; correr shell
caso "tree previo: no se quita al terminar"  '! grep -q -- "^-R" "$e/log" && [ "$rc" -eq 0 ]'

# 6. sudo con contraseña (así es en las instancias): HUMO_CLAVE se pasa con `sudo -S`, sin ella `sudo -n` falla
con_clave() { entorno; pacman_bueno
  falso sudo 'if [ "$1" != -S ]; then exit 1; fi; read -r c; [ "$c" = secreto ] || exit 1; shift; [ "$1" = -k ] && shift
[ "$1" = true ] && exit 0; exec "$@"'; }
con_clave; HUMO_CLAVE=secreto correr shell
caso "sudo con clave: HUMO_CLAVE correcta, todo OK y sale con 0"  '[ "$rc" -eq 0 ] && linea OK "sudo" >/dev/null && linea OK "instala" >/dev/null'
con_clave; HUMO_CLAVE=mala correr shell
caso "sudo con clave: HUMO_CLAVE mala, la línea de sudo es FALLA"  'linea FALLA "sudo" >/dev/null && [ "$rc" -ne 0 ]'
con_clave; correr shell
caso "sudo con clave: sin HUMO_CLAVE la línea de sudo es FALLA"  'linea FALLA "sudo" >/dev/null && [ "$rc" -ne 0 ]'

# 6b. /usr unificado (B19): /bin, /sbin y /lib resuelven dentro de /usr; la raíz de la prueba es HUMO_RAIZ (por defecto /)
raiz_falsa() { entorno; pacman_bueno; mkdir -p "$e/raiz/usr/bin" "$e/raiz/usr/sbin" "$e/raiz/usr/lib"; }
raiz_falsa; for c in bin sbin lib; do ln -s usr/$c "$e/raiz/$c"; done; correr shell HUMO_RAIZ="$e/raiz"
caso "/usr unificado: las tres enlazadas dentro de /usr es OK"  'linea OK "usr unificado" >/dev/null && [ "$rc" -eq 0 ]'
raiz_falsa; for c in sbin lib; do ln -s usr/$c "$e/raiz/$c"; done; mkdir "$e/raiz/bin"; correr shell HUMO_RAIZ="$e/raiz"
caso "/usr unificado: /bin como carpeta real es FALLA y nombra /bin"  'linea FALLA "usr unificado.*/bin" >/dev/null && [ "$rc" -ne 0 ]'
raiz_falsa; for c in bin sbin; do ln -s usr/$c "$e/raiz/$c"; done; ln -s ../tmp "$e/raiz/lib"; correr shell HUMO_RAIZ="$e/raiz"
caso "/usr unificado: /lib que sale de /usr es FALLA"  'linea FALLA "usr unificado.*/lib" >/dev/null'

# --- gpu ---
vk() { falso vulkaninfo "echo '	deviceName         = $1'"; }
gpu_entorno() { entorno; falso con-gpu 'exec "$@"'; mkdir "$e/x11"; }

# 7. vulkaninfo: Turnip OK, llvmpipe FALLA
gpu_entorno; vk 'Turnip Adreno (TM) 810'; correr gpu
caso "vulkaninfo con Turnip es OK"  'linea OK "vulkan" >/dev/null'
gpu_entorno; vk 'llvmpipe (LLVM 19.1.7, 128 bits)'; correr gpu
caso "vulkaninfo con llvmpipe es FALLA y humo.sh sale distinto de 0"  'linea FALLA "vulkan" >/dev/null && [ "$rc" -ne 0 ]'

# 8. sin vulkaninfo: SALTA con el paquete
gpu_entorno; correr gpu
caso "sin vulkaninfo: SALTA que nombra vulkan-tools"  'linea SALTA "vulkan-tools" >/dev/null'
caso "sin vulkaninfo: humo.sh sale con 0"  '[ "$rc" -eq 0 ]'

# 9. sin escritorio
gpu_entorno; vk 'Turnip Adreno (TM) 810'; correr gpu
caso "sin DISPLAY ni WAYLAND_DISPLAY: la app gráfica es SALTA (sin escritorio)"  'linea SALTA "sin escritorio" >/dev/null'

# 10. es2gears
gpu_entorno; vk 'Turnip Adreno (TM) 810'; falso es2gears_x11 'echo "GL_RENDERER = Turnip Adreno (TM) 810"; exec sleep 30'
correr gpu DISPLAY=:0
caso "es2gears vivo y sin llvmpipe: OK y sale con 0"  'linea OK "es2gears" >/dev/null && [ "$rc" -eq 0 ]'
falso es2gears_x11 'sleep 1; exit 1'; correr gpu DISPLAY=:0
caso "es2gears que muere al segundo: FALLA"  'linea FALLA "es2gears" >/dev/null'
falso es2gears_x11 'echo "GL_RENDERER = llvmpipe"; exec sleep 30'; correr gpu DISPLAY=:0
caso "es2gears que imprime llvmpipe: FALLA"  'linea FALLA "es2gears" >/dev/null'
falso es2gears_wayland 'echo "GL_RENDERER = Turnip"; exec sleep 30'
mkdir "$e/run"; python3 -c 'import socket,sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$e/run/wayland-1"
correr gpu WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR="$e/run"
caso "en Wayland se usa es2gears_wayland"  'linea OK "es2gears" >/dev/null'
mkdir "$e/x11" 2>/dev/null; : > "$e/x11/X10"; falso es2gears_x11 'echo "GL_RENDERER = Turnip"; exec sleep 30'; correr gpu
caso "escritorio detectado por el socket X11 sin DISPLAY"  'linea OK "es2gears" >/dev/null'

# Con la GPU rota, Mesa avisa por stderr y es2gears sigue vivo con software: también es FALLA
for aviso in 'MESA: error: ZINK: vkCreateInstance failed (VK_ERROR_INCOMPATIBLE_DRIVER)' 'MESA-EGL: warning: egl: failed to create dri2 screen'; do
  gpu_entorno; vk 'Turnip Adreno (TM) 810'; falso es2gears_x11 "echo '$aviso' >&2; exec sleep 30"; correr gpu DISPLAY=:0
  caso "es2gears vivo pero Mesa avisa «${aviso%%:*}...»: FALLA"  'linea FALLA "es2gears" >/dev/null'
done

# vulkaninfo solo ve Turnip a través de con-gpu (sin él, VK_ICD_FILENAMES apunta a un turnip que no sirve)
gpu_entorno; falso con-gpu 'CON_GPU=1 exec "$@"'; falso vulkaninfo '[ -n "$CON_GPU" ] || exit 1; echo "	deviceName         = Turnip Adreno (TM) 619"'
correr gpu
caso "vulkaninfo corre con con-gpu"  'linea OK "vulkan" >/dev/null'

# En X11 la sesión de la app exporta la capacidad x11-directo (con-gpu activa kopper); el script no hereda la sesión
gpu_entorno; vk 'Turnip Adreno (TM) 619'
falso es2gears_x11 'case " $ARCH_ANDROID_PROVIDER_CAPABILITIES " in *" x11-directo "*) ;; *) echo "MESA-EGL: warning: DRI3 error: Could not get DRI3 device" >&2;; esac; exec sleep 30'
correr gpu DISPLAY=:10
caso "X11: es2gears corre con la capacidad x11-directo"  'linea OK "es2gears" >/dev/null'

# WAYLAND_DISPLAY lo define la app aunque no haya escritorio: sin socket real no cuenta
gpu_entorno; vk 'Turnip Adreno (TM) 810'; falso es2gears_wayland 'echo "GL_RENDERER = Turnip"; exec sleep 30'
mkdir "$e/run"; correr gpu WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR="$e/run"
caso "WAYLAND_DISPLAY sin socket: la app gráfica es SALTA (sin escritorio)"  'linea SALTA "sin escritorio" >/dev/null'

# --- audio ---
# pw-cli falso: `info 0` responde (o no, con $e/sin-servidor) y `ls Node` lista los nodos de $e/nodos
audio_entorno() { entorno
  falso pw-cli 'if [ "$1" = info ]; then [ ! -e '"$e"'/sin-servidor ]; exit; fi; [ "$1" = ls ] && cat '"$e"'/nodos; exit 0'
  falso pw-cat 'echo "pw-cat $*" >> '"$e"'/log; cat > /dev/null; exit 0'
  echo '	node.name = "android"' > "$e/nodos"; }

# 12. el servidor responde, existe el nodo android y pw-cat acepta silencio
audio_entorno; correr audio
caso "audio: servidor, nodo android y pw-cat son OK y sale con 0"  'linea OK "servidor" >/dev/null && linea OK "android" >/dev/null && linea OK "pw-cat" >/dev/null && [ "$rc" -eq 0 ]'
caso "audio: pw-cat apunta al nodo android"  'grep -q -- "--target android" "$e/log"'

# 13. sin nodo android
audio_entorno; echo '	node.name = "alsa_output"' > "$e/nodos"; correr audio
caso "audio: sin nodo android es FALLA y sale distinto de 0"  'linea FALLA "android" >/dev/null && [ "$rc" -ne 0 ]'

# 14. sin servidor PipeWire
audio_entorno; touch "$e/sin-servidor"; correr audio
caso "audio: sin servidor es SALTA y sale con 0"  'linea SALTA "PipeWire" >/dev/null && [ "$rc" -eq 0 ]'
audio_entorno; rm "$e/bin/pw-cli"; correr audio
caso "audio: sin pw-cli es SALTA y sale con 0"  'linea SALTA "pw-cli" >/dev/null && [ "$rc" -eq 0 ]'

# --- red ---
# 15. internet por HTTPS al espejo y servidor local en la IP virtual
red_entorno() { entorno; falso curl 'echo "curl $*" >> '"$e"'/log; exit '"${1:-0}"; echo 127.0.0.1 > "$e/ip"; }
red_entorno 0; correr red HUMO_ESPEJO=https://espejo.test/ HUMO_VIRTUAL_IP="$e/ip"
caso "red: internet y servidor local son OK y sale con 0"  'linea OK "internet" >/dev/null && linea OK "servidor local" >/dev/null && [ "$rc" -eq 0 ]'
caso "red: curl va al espejo por HTTPS"  'grep -q "https://espejo.test/" "$e/log"'
red_entorno 1; correr red HUMO_ESPEJO=https://espejo.test/ HUMO_VIRTUAL_IP="$e/ip"
caso "red: curl que falla es FALLA de internet, el servidor local sigue OK"  'linea FALLA "internet" >/dev/null && linea OK "servidor local" >/dev/null && [ "$rc" -ne 0 ]'
red_entorno 0; echo 203.0.113.9 > "$e/ip"; correr red HUMO_ESPEJO=https://espejo.test/ HUMO_VIRTUAL_IP="$e/ip"
caso "red: IP virtual que no es de la instancia es FALLA de servidor local"  'linea FALLA "servidor local" >/dev/null'

red_entorno 0; rm "$e/bin/python3"; correr red HUMO_ESPEJO=https://espejo.test/ HUMO_VIRTUAL_IP="$e/ip"
caso "red: sin python3 el servidor local es SALTA que lo nombra y sale con 0"  'linea SALTA "python3" >/dev/null && [ "$rc" -eq 0 ]'

# --- batería completa ---
# todo falso en OK: shell y paquetes, gpu (sin escritorio), audio y red
todo_entorno() { audio_entorno; pacman_bueno; vk 'Turnip Adreno (TM) 619'; falso con-gpu 'exec "$@"'; mkdir -p "$e/x11"
  falso curl 'exit 0'; echo 127.0.0.1 > "$e/ip"; }

# 17. una sola falla (internet): el resumen la lista sola y sale con 1
todo_entorno; falso curl 'exit 1'; correr "" HUMO_ESPEJO=https://espejo.test/ HUMO_VIRTUAL_IP="$e/ip"
caso "completa: los cuatro grupos corren en orden"  '[ "$(sed -nE "s/^(OK|FALLA|SALTA) +([a-z]+):.*/\2/p" "$e/out" | uniq | tr "\n" " ")" = "shell paquetes gpu audio red " ]'
caso "completa: el resumen dice fallas: 1 y lista solo internet"  '[ "$(sed -n "/^fallas:/,\$p" "$e/out" | grep -c "^  - ")" -eq 1 ] && sed -n "/^fallas:/,\$p" "$e/out" | grep -q "^  - red: internet" && grep -q "^fallas: 1" "$e/out"'
caso "completa: imprime el tiempo total"  'grep -q "^tiempo: [0-9]*s" "$e/out"'
caso "completa: sale con 1"  '[ "$rc" -eq 1 ]'
todo_entorno; falso curl 'exit 0'; correr "" HUMO_ESPEJO=https://espejo.test/ HUMO_VIRTUAL_IP="$e/ip"
caso "completa: sin fallas dice fallas: 0 y sale con 0"  'grep -q "^fallas: 0" "$e/out" && [ "$rc" -eq 0 ]'

# 18. un comando colgado no traba la batería
audio_entorno; falso pw-cli 'if [ "$1" = info ]; then exit 0; fi; exec sleep 999'
t0=$SECONDS; correr audio HUMO_TOPE=3
caso "colgado: el tope de 3 s corta antes de 8 s"  '[ $((SECONDS - t0)) -lt 8 ]'
caso "colgado: el comando colgado es FALLA por tiempo"  'linea FALLA "android.*tiempo" >/dev/null'
caso "colgado: sigue con los demás comandos"  'linea OK "pw-cat" >/dev/null'
caso "colgado: no deja procesos sleep 999"  '! pgrep -x -f "^sleep 999$" >/dev/null'

echo "fallas: $fallas"
[ "$fallas" -eq 0 ]
