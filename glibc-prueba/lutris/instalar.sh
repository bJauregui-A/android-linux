#!/bin/bash
# Sube Proton 11 ARM64 (del PC) como runner "proton-11-arm64" de Lutris en arch-debian-38075 (no cierra nada).
#   lutris/instalar.sh [ruta de Proton 11.0 (ARM64)]
set -e
cd "$(dirname "$0")"
PKG=dev.ben4shot.glibcprueba.sdk36
H=files/instancias/arch-debian-38075/home/ben4shot
L=$H/.local/share/lutris
W=$L/runners/wine/proton-11-arm64
# Proton 11.0 (ARM64) = app 4628740, depot 4628741 (en el PC: steam steam://open/console → download_depot 4628740 4628741,
# o instalarlo desde la biblioteca). Ruta por defecto: la biblioteca del disco E.
SRC=${1:-"/media/ben4shot/E/SteamLibrary/steamapps/common/Proton 11.0 (ARM64)"}
if adb shell ps -A -o ARGS | grep -q '[l]utris'; then echo "Lutris está abierto: ciérralo"; exit 1; fi
run() { adb shell "run-as $PKG sh -c '$1'"; }
poner() { adb push "$1" /data/local/tmp/l-$(basename "$1") >/dev/null; run "cat /data/local/tmp/l-$(basename "$1") > $2"; adb shell rm /data/local/tmp/l-$(basename "$1"); }
[ -d "$SRC/files/bin-arm64" ] || { echo "falta $SRC"; exit 1; }
(cd "$SRC" && python3 -I -c "import sys; sys.path.insert(0, '.'); import steampipe_fixups as f; f.do_restore('.', 'steampipe_fixups.json')")
T=$(mktemp -d); trap 'rm -rf $T' EXIT
echo "empaquetando Proton…"
tar -C "$SRC" -czf $T/proton.tgz files
adb push $T/proton.tgz /data/local/tmp/proton.tgz | tail -1
adb shell chmod 644 /data/local/tmp/proton.tgz
run "mkdir -p $W/bin $H/Games && cd $W && rm -rf files && /system/bin/tar xzf /data/local/tmp/proton.tgz && ln -sfn files/lib lib && ln -sfn files/share share && ln -sfn ../files/bin-arm64/wineserver bin/wineserver && ln -sfn ../files/bin-arm64/msidb bin/msidb"
adb shell rm /data/local/tmp/proton.tgz
poner wine $W/bin/wine; run "chmod 755 $W/bin/wine"
poner wine.yml $L/runners/wine.yml
poner system.yml $L/system.yml
run "ls -la $W $W/bin; du -sh $W"
echo "listo: Lutris → runner Wine, versión proton-11-arm64"
