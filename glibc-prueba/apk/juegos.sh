#!/usr/bin/bash
# Juegos, dentro del Arch de la app (lo llama primer-arranque.sh si se eligieron): lo mismo que
# steam/instalar-steam.sh, steam/instalar-proton-directo.sh y lutris/instalar.sh, pero sin PC.
#   - cliente oficial de Steam ARM64 (beta pública de Valve) en ~/.local/share/Steam
#   - /usr/local/bin/steam (steam/steam.sh) y /usr/bin/lsof propio (steam/lsof.py)
#   - herramienta proton-directo en Steam y el Wine de Proton 11 ARM64 en Lutris
# gtk2 (/opt/gtk2) y ~/turnip-x11 ya vienen en el APK.
set -e
J=/usr/local/share/arch-android/juegos
URL=https://client-update.steamstatic.com
S=~/.local/share/Steam
T=$(mktemp -d)
trap 'rm -rf $T' EXIT

if [ ! -x $S/steamrtarm64/steam ]; then
    echo "Steam: manifiesto de la beta ARM64"
    curl -sfL $URL/steam_client_publicbeta_linuxarm64 -o $T/manifiesto.vdf
    mkdir $T/Steam
    for k in bins webkit sdl3 codecs; do
        bloque=$(grep -A4 "^	\"${k}_linuxarm64_linuxarm64\"" $T/manifiesto.vdf)
        f=$(echo "$bloque" | grep '"file"' | cut -d'"' -f4)
        sha=$(echo "$bloque" | grep '"sha2"' | cut -d'"' -f4)
        echo "bajando $f"
        curl -fL --progress-bar $URL/$f -o $T/$k.zip
        echo "$sha  $T/$k.zip" | sha256sum -c --quiet
        unzip -o -qq $T/$k.zip -d $T/Steam
        rm $T/$k.zip
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
    cd ~
    mkdir -p ~/.local/share ~/.steam
    rm -rf $S && mv $T/Steam $S
    ln -sfn $S ~/.steam/steam
    ln -sfn $S ~/.steam/root
    ln -sfn $S/linuxarm64 ~/.steam/sdkarm64
fi
install -m 755 $J/steam /usr/local/bin/steam
install -m 755 $J/lsof /usr/bin/lsof

echo "Steam: herramienta proton-directo"
P=$S/compatibilitytools.d/proton-directo
mkdir -p $P
install -m 644 $J/proton-directo/compatibilitytool.vdf $J/proton-directo/toolmanifest.vdf $P/
install -m 755 $J/proton-directo/proton $P/

echo "Lutris: Wine de Proton 11 ARM64"
L=~/.local/share/lutris
W=$L/runners/wine/proton-11-arm64
PR="$S/steamapps/common/Proton 11.0 (ARM64)/files"
mkdir -p $W/bin
install -m 755 $J/lutris/wine $W/bin/wine
ln -sfn "$PR/lib" $W/lib
ln -sfn "$PR/share" $W/share
ln -sfn "$PR/bin-arm64/wineserver" $W/bin/wineserver
ln -sfn "$PR/bin-arm64/msidb" $W/bin/msidb
install -m 644 $J/lutris/wine.yml $L/runners/wine.yml
install -m 644 $J/lutris/system.yml $L/system.yml

cat <<'EOF'

Juegos listos. Steam arranca con el escritorio; al iniciar sesión:
  - Biblioteca → instalar "Proton 11.0 (ARM64)" (lo usan proton-directo y Lutris)
  - En cada juego de Windows: Propiedades → Compatibilidad → "Proton 11 ARM64 (sin contenedor)"
EOF
