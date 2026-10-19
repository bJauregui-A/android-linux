#!/usr/bin/bash
# Compila gtk2 2.24.33 dentro del Arch de la app (Steam ARM64 lo pide: steamui.so y
# vgui2_s.so enlazan libgtk-x11-2.0.so.0, y Arch lo sacó de sus repos).
# Se instala aparte, en /opt/gtk2: steam/steam.sh lo agrega a LD_LIBRARY_PATH.
# Necesita ~/src/gtk+-2.24.33.tar.xz (de download.gnome.org, comprobar su .sha256sum).
#   scripts/compilar-en-fondo.sh compilar-gtk2.sh
set -e
V=2.24.33
GLIBC_FAKEROOT=1 pacman -S --needed --noconfirm gcc make pkgconf atk pango cairo gdk-pixbuf2 \
  libxcursor libxinerama libxrandr libxi libxcomposite libxdamage libxfixes libxext \
  shared-mime-info glib2-devel diffutils 2>&1 | tail -3
cd ~/src
[ -d gtk+-$V ] || tar xJf gtk+-$V.tar.xz
cd gtk+-$V
# Código de 2010: con gcc 15 (C23 y errores nuevos por defecto) no compila tal cual.
export CFLAGS="-O2 -std=gnu17 -Wno-error=implicit-function-declaration \
  -Wno-error=incompatible-pointer-types -Wno-error=int-conversion -Wno-error=implicit-int"
[ -f Makefile ] || ./configure --prefix=/opt/gtk2 --sysconfdir=/etc --localstatedir=/var \
  --with-xinput=yes --disable-gtk-doc --disable-introspection --disable-cups \
  --disable-static
time make -j8 CFLAGS="$CFLAGS"
GLIBC_FAKEROOT=1 make install
/opt/gtk2/bin/gtk-query-immodules-2.0 --update-cache 2>/dev/null || true
echo "=== gtk2 listo"
ls -la /opt/gtk2/lib/libgtk-x11-2.0.so.0
