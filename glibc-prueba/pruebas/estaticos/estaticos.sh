#!/usr/bin/bash
# B17: programas en Go y Rust (rg, fd, fzf, lazygit) que se saltan la glibc. Una línea por prueba: OK, FALLA o SALTA <motivo>.
# Corre DENTRO de la instancia:
#   desde el PC:  scripts/probar-en-telefono.sh <instancia> pruebas/estaticos/estaticos.sh 300
# Baja los binarios oficiales (versión y sha256 fijos, abajo) a ESTATICOS_CACHE (~/.cache/pruebas-estaticos); si ya están, no
# los baja. Sin red, sus casos son SALTA sin red; con otro sha256, FALLA y no se ejecuta. fzf y lazygit de la distro se
# instalan con la clave de sudo (HUMO_CLAVE, como humo.sh) y se quitan al terminar si no estaban.
# ESTATICOS_REPETIR=N corre cada caso N veces seguidas (falla si una falla): para las caídas intermitentes de Go.
# ESTATICOS_SOLO=<nombre> corre un solo programa (rg, fd, fzf, lazygit, fzf-distro, lazygit-distro). Sale con 0 solo si no hubo fallas.
fallas=0; lista=; inicio=$SECONDS
cache=${ESTATICOS_CACHE:-$HOME/.cache/pruebas-estaticos}

# nombre url sha256 binario-dentro-del-archivo
tabla() {
  if [ -n "$ESTATICOS_TABLA" ]; then cat "$ESTATICOS_TABLA"; return; fi
  cat <<'TABLA'
rg https://github.com/BurntSushi/ripgrep/releases/download/15.2.0/ripgrep-15.2.0-aarch64-unknown-linux-gnu.tar.gz a740b91c82eaf9914cfedd353572f2791cbe0162c84101ee0951058f4dcbc90d rg
fd https://github.com/sharkdp/fd/releases/download/v10.5.0/fd-v10.5.0-aarch64-unknown-linux-musl.tar.gz d76c4317f7d5dba69f8a2a15856c90c777e7f0dd4e85f0de8c76de6992c374d4 fd
fzf https://github.com/junegunn/fzf/releases/download/v0.74.5/fzf-0.74.5-linux_arm64.tar.gz cf058001da21724a469b714a29cf4aab9cbe860d218a0d6c1b5b661efad7784c fzf
lazygit https://github.com/jesseduffield/lazygit/releases/download/v0.66.2/lazygit_0.66.2_linux_arm64.tar.gz 79a3161eeb642f0473e23db6341f7baabd4a5933e921a9c1167c5d5c765c41a4 lazygit
TABLA
}

matar_arbol() { local h; for h in $(pgrep -P "$1"); do matar_arbol "$h"; done; kill -TERM "$1" 2>/dev/null; }
# caso <nombre> <comando> [tope-seg]: el comando corre con un tope (ESTATICOS_TOPE, 30 s) para que nada trabe la batería.
caso() {
  local pid vigia res tope=$(( ${3:-${ESTATICOS_TOPE:-30}} * ${ESTATICOS_REPETIR:-1} ))
  ( for _ in $(seq "${ESTATICOS_REPETIR:-1}"); do eval "$2" || exit $?; done ) & pid=$!
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
falla() { echo "FALLA $1"; fallas=$((fallas + 1)); lista+="$1"$'\n'; }
solo() { [ -z "$ESTATICOS_SOLO" ] || [ "$ESTATICOS_SOLO" = "$1" ]; }

# tener <nombre>: deja el binario oficial en $bin (bajado y con el sha256 de la tabla verificado). Devuelve 1 si no hay
# binario que probar: sin red (SALTA) o sha256 distinto (FALLA, y se borra el archivo).
tener() {
  local nombre url sha bin_en n arch real
  read -r n url sha bin_en < <(tabla | grep "^$1 ")
  arch=$cache/${url##*/}
  mkdir -p "$cache"
  if [ ! -e "$arch" ]; then
    curl -fsSL --max-time 120 -o "$arch.parcial" "$url" 2>/dev/null && mv "$arch.parcial" "$arch" \
      || { rm -f "$arch.parcial"; salta "$1: sin red (no se pudo bajar $url)"; return 1; }
  fi
  real=$(sha256sum "$arch" | cut -d' ' -f1)
  if [ "$real" != "$sha" ]; then rm -f "$arch"; falla "$1: sha256 distinto (esperado $sha, bajado $real)"; return 1; fi
  rm -rf "$cache/$1"; mkdir -p "$cache/$1"
  tar -xzf "$arch" -C "$cache/$1" || { falla "$1: no se pudo desempaquetar"; return 1; }
  bin=$(find "$cache/$1" -type f -name "$bin_en" | head -n 1)
  [ -n "$bin" ] || { falla "$1: el archivo no trae $bin_en"; return 1; }
  chmod +x "$bin"; echo "OK    $1: binario listo (sha256 verificado)"
}

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
# instalar_pm <paquete>: instala sin tocar el índice; si falla porque está viejo, lo actualiza una vez y reintenta.
instalar_pm() {
  salida=$(pm_instalar "$1" 2>&1) && return 0
  grep -qiE '404|could not retrieve|target not found' <<< "$salida" || return 1
  pm_indice >/dev/null 2>&1 && pm_instalar "$1" >/dev/null 2>&1
}
# paquete <nombre>: instala el de la distro. Deja en $quitar el nombre si lo instaló ahora. Devuelve 1 si la distro no lo
# tiene (SALTA).
paquete() {
  command -v "$1" >/dev/null 2>&1 && return 0
  instalar_pm "$1" && { quitar=$1; return 0; }
  salta "$1-distro: la distro no tiene el paquete $1"; return 1
}
# requisito <comando> <paquete>...: las herramientas de apoyo de los casos (git, script) se instalan si faltan y se dejan.
# Devuelve 1 (SALTA) si ningún paquete la da.
requisito() {
  local c=$1 p; shift
  command -v "$c" >/dev/null 2>&1 && return 0
  for p in "$@"; do instalar_pm "$p" >/dev/null 2>&1 && command -v "$c" >/dev/null 2>&1 && return 0; done
  salta "falta $c y no se pudo instalar ($*)"; return 1
}

# en_tty <comando> [entrada]: corre el comando en una tty de `script` de 120x40 con la entrada por stdin
en_tty() { script -qec "stty cols 120 rows 40; $1" /dev/null; }

casos_rg() {
  b=$1
  caso "rg: ve el ID de la instancia, no el de Android"  'id=$(. /etc/os-release; echo $ID); [ "$("$b" -o "^ID=.*" /etc/os-release)" = "ID=$id" ]' 30
  caso "rg: --files recorre carpetas traducidas (/var/lib/linux-android)"  '"$b" --files /var/lib/linux-android | grep -q instalado'
}
casos_fd() {
  b=$1
  caso "fd: encuentra bash en /usr/bin"  '"$b" -d1 "^bash$" /usr/bin | grep -q bash'
  caso "fd: desde /etc encuentra os-release (getcwd traducido)"  'cd /etc && "$b" -d1 os-release | grep -q os-release'
}
casos_fzf() {  # $1 = binario, $2 = etiqueta
  b=$1 et=$2
  requisito script util-linux util-linux-extra bsdutils || return
  caso "$et: --filter b arranca"  'printf "a\nb\n" | "$b" --filter b | grep -qx b'
  caso "$et: su buscador interno recorre /etc (openat directo)"  'en_tty "cd /etc && env -u FZF_DEFAULT_COMMAND $b --filter os-release" | grep -q os-release'
  caso "$et: FZF_DEFAULT_COMMAND lanza el shell (execve directo)"  'en_tty "cd /etc && FZF_DEFAULT_COMMAND=\"ls /etc\" $b --filter os-release" | grep -q os-release'
}
casos_lazygit() {  # $1 = binario, $2 = etiqueta
  b=$1 et=$2
  caso "$et: --version sale con 0"  '"$b" --version >/dev/null'
  requisito script util-linux util-linux-extra bsdutils && requisito git git || return
  caso "$et: arranca en un repo, lo ve (lanza git) y sale con q"  \
    'd=$(mktemp -d)/repo-estaticos; mkdir -p "$d" && git -C "$d" init -q && (sleep 4; printf q) | en_tty "cd $d && $b" | grep -q repo-estaticos; r=$?; rm -rf "${d%/*}"; [ $r -eq 0 ]' 40
}

if solo rg;  then tener rg  && casos_rg  "$bin"; fi
if solo fd;  then tener fd  && casos_fd  "$bin"; fi
if solo fzf; then tener fzf && casos_fzf "$bin" "fzf"; fi
if solo lazygit; then tener lazygit && casos_lazygit "$bin" "lazygit"; fi

if solo fzf-distro; then
  quitar=; paquete fzf && casos_fzf "$(command -v fzf)" "fzf-distro"
  [ -z "$quitar" ] || pm_quitar "$quitar" >/dev/null 2>&1
fi
if solo lazygit-distro; then
  if ! command -v pacman >/dev/null 2>&1; then salta "lazygit-distro: Debian no trae el paquete"
  else
    quitar=; paquete lazygit && casos_lazygit "$(command -v lazygit)" "lazygit-distro"
    [ -z "$quitar" ] || pm_quitar "$quitar" >/dev/null 2>&1
  fi
fi

echo "fallas: $fallas"
[ -z "$lista" ] || while IFS= read -r l; do echo "  - $l"; done <<< "${lista%$'\n'}"
echo "tiempo: $((SECONDS - inicio))s"
[ "$fallas" -eq 0 ]
