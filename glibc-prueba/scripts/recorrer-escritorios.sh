#!/usr/bin/bash
# Recorre los entornos gráficos cerrando la app, cambiando /var/lib/arch-android/escritorio,
# abriendo WaylandActivity, esperando unos segundos con el escritorio en pantalla y pasando al siguiente.
# Uso: scripts/recorrer-escritorios.sh [segundos=8] [entorno1 entorno2 ...]
set -eu
RAIZ=$(cd "$(dirname "$0")/.." && pwd)
PKG=${PKG:-dev.ben4shot.glibcprueba.sdk36}
ADB=(adb)
[ -n "${ANDROID_SERIAL:-}" ] && ADB+=( -s "$ANDROID_SERIAL" )

SEGUNDOS=8
if [ "${1:-}" != "" ] && [[ "${1:-}" =~ ^[0-9]+$ ]]; then
    SEGUNDOS=$1
    shift
fi

if [ "$#" -gt 0 ]; then
    IDS=("$@")
else
    mapfile -t IDS < <(sed '/^[[:space:]]*#/d; /^[[:space:]]*$/d' "$RAIZ/escritorios/orden")
fi

ANTERIOR=$("${ADB[@]}" shell run-as "$PKG" sh <<'EOF' | tr -d '\r '
cat files/archlinux/var/lib/linux-android/escritorio files/archlinux/var/lib/arch-android/escritorio 2>/dev/null | head -n 1 || echo sway
EOF
)
case "$ANTERIOR" in ''|*[!a-z0-9-]*) ANTERIOR=sway ;; esac

restaurar() {
    trap - EXIT INT TERM HUP
    printf '\n==> Restaurando escritorio (%s) y abriendo la app...\n' "$ANTERIOR"
    "${ADB[@]}" shell am force-stop "$PKG" </dev/null >/dev/null 2>&1 || true
    "${ADB[@]}" shell run-as "$PKG" sh <<EOF
mkdir -p files/archlinux/var/lib/linux-android files/archlinux/var/lib/arch-android 2>/dev/null || true
printf '%s\n' "$ANTERIOR" > files/archlinux/var/lib/linux-android/escritorio
printf '%s\n' "$ANTERIOR" > files/archlinux/var/lib/arch-android/escritorio 2>/dev/null || true
EOF
    "${ADB[@]}" shell am start -n "$PKG/dev.ben4shot.glibcprueba.WaylandActivity" </dev/null >/dev/null 2>&1 || true
}
trap restaurar EXIT INT TERM HUP

total=${#IDS[@]}
actual=0
ok_count=0
fallo_count=0

for id in "${IDS[@]}"; do
    actual=$((actual + 1))
    NOMBRE=$id
    [ -f "$RAIZ/escritorios/$id/escritorio.conf" ] && . "$RAIZ/escritorios/$id/escritorio.conf"

    printf '[%2d/%2d] %-14s (%s): cerrando app, configurando y abriendo...\n' "$actual" "$total" "$id" "$NOMBRE"
    "${ADB[@]}" shell am force-stop "$PKG" </dev/null >/dev/null
    sleep 1

    "${ADB[@]}" shell run-as "$PKG" sh <<EOF
UID_APP=\$(id -u)
mkdir -p "files/archlinux/run/user/\$UID_APP"
printf 'PENDIENTE:%s\n' "$id" > "files/archlinux/run/user/\$UID_APP/linux-session.estado"
mkdir -p files/archlinux/var/lib/linux-android files/archlinux/var/lib/arch-android 2>/dev/null || true
printf '%s\n' "$id" > files/archlinux/var/lib/linux-android/escritorio
printf '%s\n' "$id" > files/archlinux/var/lib/arch-android/escritorio 2>/dev/null || true
EOF

    "${ADB[@]}" shell am start -n "$PKG/dev.ben4shot.glibcprueba.WaylandActivity" </dev/null >/dev/null

    listo=
    fallo=
    endpoint=
    for _ in $(seq 1 40); do
        est=$("${ADB[@]}" shell run-as "$PKG" sh <<'EOF' | tr -d '\r'
for f in files/archlinux/run/user/*/linux-session.estado; do
    [ -f "$f" ] && cat "$f" && break
done
EOF
)
        case "$est" in
            "LISTO:$id:"*)
                endpoint=${est#"LISTO:$id:"}
                listo=1
                break
                ;;
            "FALLO:$id:"*)
                fallo=${est#"FALLO:$id:"}
                break
                ;;
        esac
        sleep 0.5
    done

    if [ -n "$listo" ]; then
        printf '[%2d/%2d] %-14s ABIERTO (socket=%s) — esperando %ss en pantalla...\n' "$actual" "$total" "$id" "$endpoint" "$SEGUNDOS"
        sleep "$SEGUNDOS"
        est=$("${ADB[@]}" shell run-as "$PKG" sh <<'EOF' | tr -d '\r'
for f in files/archlinux/run/user/*/linux-session.estado; do
    [ -f "$f" ] && cat "$f" && break
done
EOF
)
        case "$est" in
            "FALLO:$id:"*)
                cayo=${est#"FALLO:$id:"}
                printf '[%2d/%2d] %-14s CAYÓ durante la espera (%s)\n' "$actual" "$total" "$id" "$cayo"
                fallo_count=$((fallo_count + 1))
                ;;
            *)
                printf '[%2d/%2d] %-14s OK\n' "$actual" "$total" "$id"
                ok_count=$((ok_count + 1))
                ;;
        esac
    else
        printf '[%2d/%2d] %-14s FALLÓ (%s)\n' "$actual" "$total" "$id" "${fallo:-timeout}"
        "${ADB[@]}" shell run-as "$PKG" sh <<EOF || true
tail -n 6 "files/archlinux/tmp/$id.log" 2>/dev/null | sed 's/^/    /'
EOF
        fallo_count=$((fallo_count + 1))
    fi
done

printf '============================================================\n'
printf 'Resumen: %d OK, %d con fallo (de %d).\n' "$ok_count" "$fallo_count" "$total"
