#!/usr/bin/bash
# Instalador de ayudantes de AUR desde los repositorios oficiales de aur.archlinux.org
set -e

instalar_aur_pkg() {
    local pkg=$1
    local repo="https://aur.archlinux.org/${pkg}.git"
    printf '\e[1;38;5;81m==> Instalando %s desde %s...\e[0m\n' "$pkg" "$repo"
    local tmp
    tmp=$(mktemp -d)
    if git clone --depth 1 "$repo" "$tmp/$pkg"; then
        (
            cd "$tmp/$pkg"
            # Si es necesario compilar con Go o Rust, makepkg resolverá o usará las herramientas del sistema
            GLIBC_FAKEROOT=1 makepkg -si --noconfirm -A
        )
        rm -rf "$tmp"
        printf '\e[1;38;5;48m✔ %s instalado correctamente\e[0m\n' "$pkg"
    else
        printf '\e[1;38;5;196m✖ Falló la clonación de %s desde AUR\e[0m\n' "$pkg"
        rm -rf "$tmp"
        return 1
    fi
}

if [ $# -eq 0 ]; then
    set -- yay-bin
fi

for a in "$@"; do
    case "$a" in
        yay|yay-bin|paru|paru-bin)
            instalar_aur_pkg "$a"
            ;;
        *)
            echo "Paquete no reconocido: $a (usar yay, yay-bin, paru o paru-bin)"
            ;;
    esac
done
