#!/usr/bin/bash
# Barrido acotado para la variante APK de diagnóstico. No instala ni cambia paquetes.
set +e
D=/usr/local/share/arch-android/escritorios
R=/tmp/diagnostico-escritorios.log
E=/var/lib/arch-android
export ANDROID_ESCALA=${ANDROID_ESCALA:-2.5}
export XKB_DEFAULT_LAYOUT=${XKB_DEFAULT_LAYOUT:-latam}
export XDG_SESSION_TYPE=wayland
taskset -p ff $$ >/dev/null 2>&1
cd "$HOME"

printf 'Diagnóstico Wayland: %s\n' "$(date)" > "$R"
printf 'Dispositivo: %s\nWayland anfitrión: %s/%s\n\n' "$ANDROID_MODELO" "$XDG_RUNTIME_DIR" "$WAYLAND_DISPLAY" >> "$R"

config() {
    [ -d "$D/$1/home" ] || return 0
    (cd "$D/$1/home" && find . -type f) | while read -r f; do
        [ -e "$HOME/$f" ] && continue
        mkdir -p "$HOME/$(dirname "$f")"
        sed "s/@ESCALA@/$ANDROID_ESCALA/g" "$D/$1/home/$f" > "$HOME/$f"
        [ -x "$D/$1/home/$f" ] && chmod +x "$HOME/$f"
    done
}

required() {
    case "$1" in
        labwc) echo labwc;; xfce) echo 'labwc xfce4-session';; lxqt) echo startlxqtwayland;;
        kde) echo 'dbus-run-session startplasma-wayland';; plasma-movil) echo 'dbus-run-session startplasmamobile';;
        phosh) echo phoc;; niri) echo niri;; cosmic) echo cosmic-session;;
        wayfire) echo wayfire;; river) echo river;; qtile) echo qtile;; weston) echo weston;;
    esac
}

for id in $(sed '/^[[:space:]]*#/d; /^[[:space:]]*$/d' "$D/orden"); do
    [ "$id" = sway ] && continue
    if [ ! -f "$D/$id/sesion" ]; then
        printf '%-14s SIN PERFIL\n' "$id" | tee -a "$R"
        continue
    fi
    bins=$(required "$id")
    faltan=
    for bin in $bins; do
        command -v "$bin" >/dev/null 2>&1 || faltan="$faltan $bin"
    done
    if [ -n "$faltan" ]; then
        printf '%-14s NO INSTALADO (%s)\n' "$id" "${faltan# }" | tee -a "$R"
        continue
    fi

    config "$id"
    export WAYLAND_DISPLAY=wayland-0
    anteriores=" $(for s in "$XDG_RUNTIME_DIR"/wayland-*; do [ -S "$s" ] && printf '%s ' "${s##*/}"; done) "
    log="/tmp/diag-$id.log"
    printf '\n===== %s (%s) =====\n' "$id" "$(date)" > "$log"
    setsid /usr/bin/bash "$D/$id/sesion" >> "$log" 2>&1 &
    pid=$!
    socket=
    estado=
    # Hasta 12 s para publicar un socket Wayland nuevo.
    for i in $(seq 1 48); do
        for s in "$XDG_RUNTIME_DIR"/wayland-*; do
            [ -S "$s" ] || continue
            case "$anteriores" in *" ${s##*/} "*) continue;; esac
            socket=$s
            break 2
        done
        if ! kill -0 "$pid" 2>/dev/null; then estado=termino; break; fi
        sleep 0.25
    done

    if [ -n "$socket" ]; then
        sleep 3
        if kill -0 "$pid" 2>/dev/null; then
            estado="OK: socket ${socket##*/}, activo 3 s"
        else
            estado="FALLO: publicó socket y terminó"
        fi
    elif [ -z "$estado" ]; then
        estado="TIMEOUT: sin socket en 12 s"
    else
        estado="FALLO: terminó antes de publicar socket"
    fi

    printf '%-14s %s\n' "$id" "$estado" | tee -a "$R"
    if [ "$estado" != "NO INSTALADO" ]; then
        kill -TERM -- "-$pid" 2>/dev/null
        for i in $(seq 1 12); do
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.25
        done
        kill -KILL -- "-$pid" 2>/dev/null
        wait "$pid" 2>/dev/null
    fi
    printf 'Log: %s\n' "$log" >> "$R"
done

printf '\nFin del barrido: %s\nRegistros: %s y /tmp/diag-<entorno>.log\n' "$(date)" "$R" >> "$R"
notify-send 'Diagnóstico gráfico terminado' 'Resultados en /tmp/diagnostico-escritorios.log' 2>/dev/null
exec /usr/bin/bash "$D/sway/sesion" >> /tmp/sway.log 2>&1
