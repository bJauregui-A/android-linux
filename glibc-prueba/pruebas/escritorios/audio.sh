#!/usr/bin/bash
# B11: audio hacia Android en cualquier escritorio (también los X11), con varias instancias a la vez.
# Corre en el PC, sobre las carpetas reales del repo:  pruebas/escritorios/audio.sh
cd "$(dirname "$0")/../.." || exit 1
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }
AUTO=escritorios/autostart-android
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# Todos los procesos de la app se ven entre instancias: `pgrep -x pipewire` encuentra el de sway y el X11 se queda
# sin PipeWire propio (sin el FIFO tmp/audio-android que lee Audio.java).
caso "el supervisor no decide por un pgrep de pipewire"  '! grep -q "pgrep -x pipewire" $AUTO'
eval "$(sed -n '/^pipewire_propio() {/,/^}/p' $AUTO)"
caso "el supervisor tiene pipewire_propio"  'type pipewire_propio >/dev/null 2>&1'
mkdir -p "$tmp/bin"
printf '#!/bin/sh\nexit 0\n' > "$tmp/bin/pw-cli"; chmod +x "$tmp/bin/pw-cli"
caso "pipewire_propio: el servidor de la instancia responde"  'PATH="$tmp/bin:$PATH" pipewire_propio'
printf '#!/bin/sh\nexit 1\n' > "$tmp/bin/pw-cli"
caso "pipewire_propio: el de la instancia no responde (aunque corra otro)"  '! PATH="$tmp/bin:$PATH" pipewire_propio'
caso "el arranque de pipewire usa pipewire_propio"  'grep -q "^if \[ -x /usr/bin/pipewire \] && ! pipewire_propio" $AUTO'

# speaker-test y las apps ALSA: sin pipewire-alsa no hay PCM "default" ("Unknown PCM default").
caso "audio de Arch trae pipewire-alsa"    'sed "s/#.*//" apk/paquetes-audio.txt | grep -qw pipewire-alsa'
caso "audio de Debian trae pipewire-alsa"  'sed "s/#.*//" apk/paquetes-audio-apt.txt | grep -qw pipewire-alsa'

# El sink hacia Android va en la capa común (todas las instancias), no en la receta de sway.
caso "10-android.conf va en la capa común"  'grep -q "pipewire/10-android.conf" apk/capa.py'

echo "fallas: $fallas"
[ "$fallas" -eq 0 ]
