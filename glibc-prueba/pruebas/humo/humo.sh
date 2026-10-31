#!/usr/bin/bash
# B16: batería de pruebas de humo de una instancia (Arch o Debian). Una línea por prueba: OK, FALLA o SALTA <motivo>.
# Corre DENTRO de la instancia:
#   desde el PC:  scripts/probar-en-telefono.sh <instancia> pruebas/humo/humo.sh 90
#   desde kitty:  bash pruebas/humo/humo.sh
# Corre los cuatro grupos en orden (shell y paquetes, gpu, audio, red); cada comando tiene un tope (HUMO_TOPE, 30 s) y al final
# imprime fallas: N, lo que falló y el tiempo total.
# HUMO_SOLO=<grupo> corre un solo grupo (shell, gpu, audio, red). Sale con 0 solo si no hubo fallas.
# HUMO_CLAVE=<contraseña> es la de sudo (en las instancias sudo la pide); sin ella se usa `sudo -n`.
fallas=0; lista=; inicio=$SECONDS
# Mata un proceso y todos sus descendientes (timeout y otros se ponen en su propio grupo: no sirve matar por grupo).
matar_arbol() { local h; for h in $(pgrep -P "$1"); do matar_arbol "$h"; done; kill -TERM "$1" 2>/dev/null; }
# caso <nombre> <comando> [tope-seg]: el comando corre con un tope (HUMO_TOPE, 30 s) para que nada trabe la batería.
caso() {
  local pid vigia res tope=${3:-${HUMO_TOPE:-30}}
  ( eval "$2" ) & pid=$!
  ( sleep "$tope"; touch "$cola.$pid"; matar_arbol "$pid" ) & vigia=$!
  wait "$pid"; res=$?
  if [ -e "$cola.$pid" ]; then rm -f "$cola.$pid"; echo "FALLA $1 (tiempo: más de ${tope}s)"; fallas=$((fallas + 1)); lista+="$1 (tiempo)"$'\n'
  elif [ "$res" -eq 0 ]; then echo "OK    $1"
  else echo "FALLA $1"; fallas=$((fallas + 1)); lista+="$1"$'\n'
  fi
  kill "$vigia" 2>/dev/null; wait "$vigia" 2>/dev/null
}
cola=$(mktemp -u)
salta() { echo "SALTA $1"; }
grupo() { [ -z "$HUMO_SOLO" ] || [ "$HUMO_SOLO" = "$1" ]; }

como_root() {
  if [ -n "$HUMO_CLAVE" ]; then printf '%s\n' "$HUMO_CLAVE" | sudo -S -k "$@" 2>&1 | grep -v '^\[sudo\]'; return "${PIPESTATUS[1]}"
  else sudo -n "$@"; fi
}

if command -v pacman >/dev/null 2>&1; then
  pm_instalar() { como_root pacman -S --noconfirm "$1"; }
  pm_quitar() { como_root pacman -R --noconfirm "$1"; }
  pm_indice() { como_root pacman -Sy --noconfirm; }
else
  pm_instalar() { como_root apt-get install -y "$1"; }
  pm_quitar() { como_root apt-get remove -y "$1"; }
  pm_indice() { como_root apt-get update; }
fi
# Instala sin tocar el índice; solo si falla porque está viejo lo actualiza una vez y reintenta.
instalar() {
  salida=$(pm_instalar "$1" 2>&1) && return 0
  grep -qiE '404|could not retrieve|target not found' <<< "$salida" || return 1
  pm_indice >/dev/null 2>&1 && pm_instalar "$1" >/dev/null 2>&1
}

if grupo shell; then
  caso "shell: bash corre comandos"  '[ "$(bash -c "echo hola")" = hola ]'
  caso "shell: sudo funciona"  'como_root true >/dev/null'
  # B47: la raíz es de root y tiene el modo de su distro: Debian 755; Arch 555
  caso "shell: raíz root:root con el modo de su distro"  'r=$(stat -c "%a %U:%G" "${HUMO_RAIZ:-/}"); if command -v pacman >/dev/null 2>&1; then [ "$r" = "555 root:root" ]; else [ "$r" = "755 root:root" ]; fi'
  caso "shell: sudo mkdir crea y borra una carpeta en /"  'como_root mkdir "${HUMO_RAIZ%/}/x" && como_root rmdir "${HUMO_RAIZ%/}/x"'
  # B95: root salta los permisos de archivos y carpetas (lee un 000, escribe en un 444, crea en una 555)
  # (sin capturar la salida de como_root: su filtro del aviso de sudo se come la línea si el aviso queda pegado a ella)
  caso "shell: sudo lee un 000, escribe en un 444 y crea en una 555"  'd=$(mktemp -d) || exit 1
    echo dato > "$d/a"; chmod 000 "$d/a"; echo uno > "$d/b"; chmod 444 "$d/b"; mkdir "$d/c"; chmod 555 "$d/c"
    r=0
    como_root grep -qx dato "$d/a" || { echo "  sudo no lee un 000" >&2; r=1; }
    como_root sh -c "echo dos >> \"\$1\"" _ "$d/b" && [ "$(cat "$d/b")" = "$(printf "uno\ndos")" ] || { echo "  sudo no escribe en un 444" >&2; r=1; }
    como_root mkdir "$d/c/x" && [ -d "$d/c/x" ] || { echo "  sudo no crea en una 555" >&2; r=1; }
    chmod 755 "$d/c"; chmod 644 "$d/a"; rm -rf "$d"; [ $r -eq 0 ]'
  caso "shell: /tmp escribe y lee"   'f=$(mktemp) && echo dato > "$f" && [ "$(cat "$f")" = dato ]; r=$?; rm -f "$f"; [ $r -eq 0 ]'
  # /usr unificado: /bin, /sbin y /lib son enlaces que resuelven dentro de /usr (HUMO_RAIZ cambia la raíz, para las pruebas)
  for c in bin sbin lib; do
    caso "shell: usr unificado: /$c resuelve dentro de /usr"  'case "$(readlink -f "${HUMO_RAIZ%/}/'$c'")/" in "$(readlink -f "${HUMO_RAIZ%/}/usr")"/*) ;; *) false;; esac'
  done
  command -v tree >/dev/null 2>&1 && previo=1
  caso "paquetes: instala tree"  'instalar tree' 120
  if [ -n "$previo" ]; then salta "paquetes: tree ya estaba instalado, no se quita"
  else caso "paquetes: quita tree"  'pm_quitar tree >/dev/null 2>&1' 60
  fi
fi

# Escritorio abierto: DISPLAY del entorno o un socket real, X11 o Wayland. WAYLAND_DISPLAY solo no cuenta (la app lo define
# sin escritorio) y probar-en-telefono.sh no hereda la sesión, así que se buscan los sockets.
escritorio() {
  [ -n "$DISPLAY" ] && return 0
  local run=${XDG_RUNTIME_DIR:-/run/user/$(id -u)} x f
  [ -n "$WAYLAND_DISPLAY" ] && [ -S "$run/$WAYLAND_DISPLAY" ] && return 0
  x=$(ls "${HUMO_X11_DIR:-/tmp/.X11-unix}" 2>/dev/null | grep -m1 '^X[0-9]')
  [ -n "$x" ] && { export DISPLAY=:${x#X}; return 0; }
  for f in "$run"/wayland-[0-9]; do
    [ -S "$f" ] && { export WAYLAND_DISPLAY=${f##*/}; return 0; }
  done
  return 1
}
# es2gears unos segundos por la GPU: sigue vivo hasta que se lo corta, no dice llvmpipe ni softpipe y Mesa no avisa de
# errores (con la GPU rota Zink falla y es2gears sigue vivo con software).
gears() (
  # la sesión X11 de la app exporta x11-directo (kopper); probar-en-telefono.sh no la hereda (como en pruebas/x11/gl.sh)
  if [ "$1" = es2gears_x11 ]; then
    unset LD_PRELOAD MESA_LOADER_DRIVER_OVERRIDE LIBGL_KOPPER_DRI2 GALLIUM_DRIVER
    export ARCH_ANDROID_PROVIDER_CAPABILITIES=${ARCH_ANDROID_PROVIDER_CAPABILITIES:-x11-directo}
  fi
  local log pid vivo
  log=$(mktemp); con-gpu stdbuf -oL "$1" > "$log" 2>&1 & pid=$!
  sleep "${HUMO_GPU_SEGUNDOS:-4}"
  kill -0 "$pid" 2>/dev/null && vivo=1
  kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
  ! grep -qiE 'llvmpipe|softpipe|^MESA(-EGL)?: (error|warning)' "$log"; local limpio=$?
  rm -f "$log"
  [ -n "$vivo" ] && [ "$limpio" -eq 0 ]
)

if grupo gpu; then
  if ! command -v vulkaninfo >/dev/null 2>&1; then salta "gpu: vulkan (falta vulkan-tools)"
  else caso "gpu: vulkaninfo muestra Turnip"  'timeout 20 con-gpu vulkaninfo --summary 2>/dev/null | grep -qE "deviceName.*(Adreno|Turnip)"'
  fi
  if ! escritorio; then salta "gpu: es2gears (sin escritorio)"
  else
    if [ -n "$WAYLAND_DISPLAY" ] && [ -z "$DISPLAY" ]; then app=es2gears_wayland; else app=es2gears_x11; fi
    if ! command -v "$app" >/dev/null 2>&1; then salta "gpu: es2gears (falta mesa-utils: $app)"
    else caso "gpu: es2gears ($app) vivo por la GPU"  'gears "$app"'
    fi
  fi
fi

if grupo audio; then
  if ! command -v pw-cli >/dev/null 2>&1; then salta "audio: falta pw-cli (grupo de audio: pipewire)"
  elif ! timeout 10 pw-cli info 0 >/dev/null 2>&1; then salta "audio: sin PipeWire corriendo"
  else
    echo "OK    audio: servidor PipeWire responde"
    caso "audio: existe el nodo android"  'timeout 10 pw-cli ls Node 2>/dev/null | grep -q "node.name = \"android\""'
    # 1 s de silencio crudo (s16, 48 kHz, estéreo): no suena nada
    caso "audio: pw-cat acepta silencio hacia android"  'head -c 192000 /dev/zero | timeout 15 pw-cat --playback --raw --target android -'
  fi
fi

# URL del espejo de la distro (la primera de mirrorlist o sources.list), sin los $arch/$repo
espejo() {
  [ -n "$HUMO_ESPEJO" ] && { echo "$HUMO_ESPEJO"; return; }
  cat /etc/pacman.d/mirrorlist /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null | grep -v '^ *#' | grep -oE 'https?://[^ $]+' | head -n 1
}
# Servidor de prueba que escucha en la IP virtual de la instancia y al que se conecta la misma instancia
servidor_local() {
  python3 - "$(cat "${HUMO_VIRTUAL_IP:-/etc/virtual-ip}")" <<'PY'
import socket, sys
srv = socket.socket(); srv.settimeout(5); srv.bind((sys.argv[1], 0)); srv.listen(1)
cli = socket.create_connection(srv.getsockname(), timeout=5)
con, _ = srv.accept(); cli.sendall(b"humo"); sys.exit(0 if con.recv(4) == b"humo" else 1)
PY
}

if grupo red; then
  caso "red: internet (curl al espejo)"  'u=$(espejo); [ -n "$u" ] && timeout 20 curl -fsIL --max-time 15 "$u" >/dev/null'
  if ! command -v python3 >/dev/null 2>&1; then salta "red: servidor local (falta python3)"
  else caso "red: servidor local en la IP virtual"  'servidor_local 2>/dev/null'
  fi
fi

echo "fallas: $fallas"
[ -z "$lista" ] || while IFS= read -r l; do echo "  - $l"; done <<< "${lista%$'\n'}"
echo "tiempo: $((SECONDS - inicio))s"
[ "$fallas" -eq 0 ]
