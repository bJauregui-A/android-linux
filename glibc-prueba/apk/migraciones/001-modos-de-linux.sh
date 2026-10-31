#!/usr/bin/bash
# B96: los procesos de la app corrían con umask 077 y lo que crearon quedó 600/700, ilegible para los demás usuarios. Deja con
# modo de Linux lo de la app: los archivos de red de /etc (solo si siguen en 600) y lo compilado en usr/local. No toca lo que
# en Linux también es privado (shadow, claves, sudoers). Se puede correr dos veces. MIGRAR_RAIZ solo lo usa la prueba del PC.
R=${MIGRAR_RAIZ:-}
for f in etc/resolv.conf etc/hostname etc/hosts etc/virtual-ip; do
    if [ -f "$R/$f" ] && [ ! -L "$R/$f" ] && [ "$(stat -c %a "$R/$f")" = 600 ]; then
        chmod 644 "$R/$f"
    fi
done
for d in turnip turnip-x11 mesa-gl sway wlroots; do
    [ -d "$R/usr/local/$d" ] && chmod -R go+rX "$R/usr/local/$d"
done
exit 0
