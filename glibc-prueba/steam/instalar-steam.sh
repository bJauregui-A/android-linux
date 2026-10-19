#!/bin/bash
# Instala el cliente oficial de Steam para Linux ARM64 (beta pública de Valve, no enlazada
# en su web) en ~/.local/share/Steam del Arch de la app, sin cerrar la app.
# Baja del manifiesto de Valve los paquetes mínimos (cliente, CEF, SDL3, códecs), comprueba
# su sha256, arregla los enlaces simbólicos guardados con "\" y lo sube al teléfono.
# El resto lo baja Steam al actualizarse. Dependencias de Arch: ver PROYECTO.md (11ª sesión).
#   steam/instalar-steam.sh
set -e
cd "$(dirname "$0")/.."
PKG=dev.ben4shot.glibcprueba.sdk36
URL=https://client-update.steamstatic.com
T=$(mktemp -d)
trap 'rm -rf $T' EXIT
curl -sf $URL/steam_client_publicbeta_linuxarm64 -o $T/manifiesto.vdf
mkdir $T/Steam
for k in bins webkit sdl3 codecs; do
  bloque=$(grep -A4 "^	\"${k}_linuxarm64_linuxarm64\"" $T/manifiesto.vdf)
  f=$(echo "$bloque" | grep '"file"' | cut -d'"' -f4)
  sha=$(echo "$bloque" | grep '"sha2"' | cut -d'"' -f4)
  echo "bajando $f"
  curl -sf $URL/$f -o $T/$k.zip
  echo "$sha  $T/$k.zip" | sha256sum -c --quiet
  unzip -o -qq $T/$k.zip -d $T/Steam
done
# Entradas "steamrtarm64\video\libvpx.so.6" (enlaces): pasarlas a carpetas de verdad.
python3 -I - "$T/Steam" <<'EOF'
import os, sys
os.chdir(sys.argv[1])
for n in sorted(os.listdir('.'), key=lambda n: os.path.isdir(n) and not os.path.islink(n)):
    if '\\' not in n: continue
    p = n.replace('\\', '/')
    if os.path.islink(n):
        os.makedirs(os.path.dirname(p), exist_ok=True)
        if not os.path.lexists(p): os.symlink(os.readlink(n), p)
        os.remove(n)
    else:
        os.makedirs(p, exist_ok=True); os.rmdir(n)
EOF
cd $T/Steam
mkdir -p package logs && echo publicbeta > package/beta
ln -sfn steamrtarm64 steamrt64
touch .steam-enable-steamrt64-client
chmod -R u+rwX .
find steamrtarm64 -maxdepth 1 -type f \( -name '*.sh' -o -exec sh -c 'file -b "$1" | grep -q "ELF.*executable"' _ {} \; \) -exec chmod +x {} +
cd $T && tar czf steam.tgz Steam
adb push $T/steam.tgz /data/local/tmp/steam.tgz
adb shell chmod 644 /data/local/tmp/steam.tgz
F=/data/data/$PKG/files/archlinux
adb shell "run-as $PKG sh -c 'mkdir -p $F/home/user/.local/share $F/home/user/.steam && cd $F/home/user/.local/share && /system/bin/tar xzf /data/local/tmp/steam.tgz \
  && ln -sfn /home/user/.local/share/Steam $F/home/user/.steam/steam && ln -sfn /home/user/.local/share/Steam $F/home/user/.steam/root \
  && ln -sfn /home/user/.local/share/Steam/linuxarm64 $F/home/user/.steam/sdkarm64'"
adb shell rm /data/local/tmp/steam.tgz
adb push steam/steam.sh /data/local/tmp/steam.sh >/dev/null
adb shell "run-as $PKG sh -c 'cp /data/local/tmp/steam.sh $F/usr/local/bin/steam && chmod 755 $F/usr/local/bin/steam'"
adb shell rm /data/local/tmp/steam.sh
echo "Steam instalado: abrir con 'steam' desde kitty (necesita gtk2: steam/compilar-gtk2.sh)"
