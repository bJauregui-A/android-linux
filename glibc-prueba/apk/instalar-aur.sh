#!/usr/bin/bash
# Instalador de ayudantes de AUR (yay y paru) para Arch Linux ARM64
set -euo pipefail

YAY_VER="13.0.1"
PARU_VER="2.1.0"

instalar_yay() {
    printf '\e[1;38;5;81m==> Instalando yay (v%s aarch64)...\e[0m\n' "$YAY_VER"
    local url="https://github.com/Jguer/yay/releases/download/v${YAY_VER}/yay_${YAY_VER}_aarch64.tar.gz"
    local tmp
    tmp=$(mktemp -d)
    
    if curl -fSL --retry 3 "$url" -o "$tmp/yay.tar.gz" 2>/dev/null || wget -q "$url" -O "$tmp/yay.tar.gz"; then
        tar -xzf "$tmp/yay.tar.gz" -C "$tmp"
        local d="$tmp/yay_${YAY_VER}_aarch64"
        if [ -f "$d/yay" ]; then
            sudo install -Dm755 "$d/yay" /usr/local/bin/yay
            sudo ln -sf /usr/local/bin/yay /usr/bin/yay 2>/dev/null || true
            [ -f "$d/yay.8" ] && sudo install -Dm644 "$d/yay.8" /usr/local/share/man/man8/yay.8 2>/dev/null || true
            [ -f "$d/bash" ] && sudo install -Dm644 "$d/bash" /usr/share/bash-completion/completions/yay 2>/dev/null || true
            [ -f "$d/zsh" ] && sudo install -Dm644 "$d/zsh" /usr/share/zsh/site-functions/_yay 2>/dev/null || true
            rm -rf "$tmp"
            printf '    \e[1;38;5;48m✔ yay instalado correctamente en /usr/local/bin/yay\e[0m\n'
            return 0
        fi
    fi
    rm -rf "$tmp"
    printf '    \e[1;38;5;196m✖ No se pudo descargar el binario de yay desde GitHub\e[0m\n'
    return 1
}

instalar_paru() {
    printf '\e[1;38;5;81m==> Instalando paru (v%s aarch64)...\e[0m\n' "$PARU_VER"
    local url="https://github.com/Morganamilo/paru/releases/download/v${PARU_VER}/paru-v${PARU_VER}-aarch64.tar.zst"
    local tmp
    tmp=$(mktemp -d)
    
    if curl -fSL --retry 3 "$url" -o "$tmp/paru.tar.zst" 2>/dev/null || wget -q "$url" -O "$tmp/paru.tar.zst"; then
        tar --zstd -xf "$tmp/paru.tar.zst" -C "$tmp" 2>/dev/null || tar -xf "$tmp/paru.tar.zst" -C "$tmp"
        if [ -f "$tmp/paru" ]; then
            sudo install -Dm755 "$tmp/paru" /usr/local/bin/paru
            sudo ln -sf /usr/local/bin/paru /usr/bin/paru 2>/dev/null || true
            [ -f "$tmp/paru.conf" ] && sudo install -Dm644 "$tmp/paru.conf" /etc/paru.conf 2>/dev/null || true
            rm -rf "$tmp"
            printf '    \e[1;38;5;48m✔ paru instalado correctamente en /usr/local/bin/paru\e[0m\n'
            return 0
        fi
    fi
    rm -rf "$tmp"
    printf '    \e[1;38;5;196m✖ No se pudo descargar el binario de paru desde GitHub\e[0m\n'
    return 1
}

if [ $# -eq 0 ]; then
    set -- yay-bin
fi

for a in "$@"; do
    case "$a" in
        yay|yay-bin)
            instalar_yay || true
            ;;
        paru|paru-bin)
            instalar_paru || true
            ;;
        *)
            echo "Paquete no reconocido: $a (usar yay, yay-bin, paru o paru-bin)"
            ;;
    esac
done
