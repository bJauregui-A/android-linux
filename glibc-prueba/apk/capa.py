#!/usr/bin/env python3
"""Arma capa.tar: lo nuestro encima del Arch de la app (lo que hoy suben los scripts subir-*.sh).

  - lo compilado en el teléfono (trabajo/compilados.tar, de apk/traer-compilados.sh):
    ~/wlroots, ~/sway, ~/turnip, ~/turnip-x11 y ~/mesa-gl pasan a /usr/local/<nombre> (el
    usuario se elige al instalar); /home/user/ dentro de los archivos, binarios incluidos, se
    cambia por /usr/local/ (mismo largo). /opt/gtk2 queda igual. Los enlaces con la ruta del
    prefijo de origen pasan al de destino
  - configs y scripts del repo en su lugar; lo del usuario en /etc/skel (primer-arranque.sh
    lo copia al home elegido)
  - el instalador (apk/) y los escritorios para elegir (escritorios/) en /usr/local/share/arch-android

Uso: capa.py --prefix /data/user/0/<paquete>/files/archlinux --compilados trabajo/compilados.tar --out capa.tar
"""
import argparse
import io
import os
import re
import subprocess
import tarfile
import tempfile
import time

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # glibc-prueba/
H = "etc/skel"  # → /home/<usuario>
D = "usr/local/share/linux-android"
STRIP = os.path.expanduser("~/Android/Sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip")
# Respaldos de bibliotecas (libgallium...so.0001) y documentación: no van
SALTAR = re.compile(r"\.\d{4}$|/share/(gtk-doc|man|doc)/")
VIEJO, NUEVO = b"/home/user/", b"/usr/local/"
assert len(VIEJO) == len(NUEVO)

# (origen en el repo, destino en el prefijo, modo)
ARCHIVOS = [
    ("sway/config", f"{H}/.config/sway/config", 0o644),
    ("sway/opacidad.py", f"{H}/.config/sway/opacidad.py", 0o644),
    ("sway/nucleos.py", f"{H}/.config/sway/nucleos.py", 0o644),
    ("sway/ventanas.sh", f"{H}/.config/sway/ventanas.sh", 0o755),
    ("sway/escritorio-vacio.sh", f"{H}/.config/sway/escritorio-vacio.sh", 0o755),
    ("sway/atajos.sh", f"{H}/.config/sway/atajos.sh", 0o755),
    ("sway/waybar/config.jsonc", f"{H}/.config/waybar/config.jsonc", 0o644),
    ("sway/waybar/style.css", f"{H}/.config/waybar/style.css", 0o644),
    ("sway/fuzzel/fuzzel.ini", f"{H}/.config/fuzzel/fuzzel.ini", 0o644),
    ("sway/kitty/kitty.conf", f"{H}/.config/kitty/kitty.conf", 0o644),
    ("sway/kitty/hyde.conf", f"{H}/.config/kitty/hyde.conf", 0o644),
    ("sway/kitty/theme.conf", f"{H}/.config/kitty/theme.conf", 0o644),
    ("sway/zsh/.zshrc", f"{H}/.zshrc", 0o644),
    ("sway/zsh/starship.toml", f"{H}/.config/starship/starship.toml", 0o644),
    ("sway/pipewire/10-android.conf", f"{H}/.config/pipewire/pipewire.conf.d/10-android.conf", 0o644),
    ("sway/dbus-sesion.sh", "etc/profile.d/dbus-sesion.sh", 0o644),
    ("supervisor/supervisor.sh", "etc/profile.d/supervisor.sh", 0o644),
    ("android/android-abrir", "usr/local/bin/android-abrir", 0o755),
    ("android/xdg-open", "usr/local/bin/xdg-open", 0o755),
    ("android/reajustar-pantalla", "usr/local/bin/reajustar-pantalla", 0o755),
    ("android/android-shm-limpiar", "usr/local/bin/android-shm-limpiar", 0o755),
    ("android/android-notificaciones", "usr/local/bin/android-notificaciones", 0o755),
    ("android/org.freedesktop.Notifications.service",
     f"{H}/.local/share/dbus-1/services/org.freedesktop.Notifications.service", 0o644),
    ("android/android-abrir.desktop", f"{H}/.local/share/applications/android-abrir.desktop", 0o644),
    ("android/mimeapps.list", f"{H}/.config/mimeapps.list", 0o644),
    ("mesa-gl/con-gpu", "usr/local/bin/con-gpu", 0o755),
    ("mesa-gl/firefox", "usr/local/bin/firefox", 0o755),
    ("supervisor/service-daemon", "usr/local/bin/service-daemon", 0o755),
    ("supervisor/service", "usr/local/bin/service", 0o755),
    ("supervisor/service", "usr/local/bin/sv", 0o755),
    ("glibc/salida/usr/lib/libc.so.6", "usr/lib/libc.so.6", 0o755),
    ("trabajo/libudmabuf-shim.so", "usr/local/lib/libudmabuf-shim.so", 0o755),
    ("scripts/adb-conectar", "usr/local/bin/adb-conectar", 0o755),
    ("android/proxy-ssh-22", "usr/local/bin/proxy-ssh-22", 0o755),
    ("android/proxy-ssh-22-daemon", f"{D}/proxy-ssh-22-daemon", 0o755),
    ("android/proxy-ssh-22-worker", f"{D}/proxy-ssh-22-worker", 0o755),
    ("apk/pacman-xfer", "usr/local/bin/pacman-xfer", 0o755),
    # escritorio elegido al instalar (escritorios/: uno por carpeta) y lo que arranca con todos
    ("escritorios/sesion-android", "usr/local/bin/sesion-android", 0o755),
    ("escritorios/autostart-android", "usr/local/bin/autostart-android", 0o755),
    ("escritorios/recorrer-escritorios", "usr/local/bin/recorrer-escritorios", 0o755),
    ("apk/sshd-android.conf", "etc/ssh/sshd_config.d/10-android.conf", 0o644),
    # instalador (primer arranque) y lo que instala después
    ("apk/primer-arranque.sh", f"{D}/primer-arranque.sh", 0o755),
    ("apk/instalar-aur.sh", f"{D}/instalar-aur.sh", 0o755),
    ("apk/instalar-aur.sh", "usr/local/bin/instalar-aur", 0o755),
    ("apk/juegos.sh", f"{D}/juegos.sh", 0o755),
    ("steam/steam.sh", f"{D}/juegos/steam", 0o755),
    ("steam/lsof.py", f"{D}/juegos/lsof", 0o755),
    ("steam/proton-directo/compatibilitytool.vdf", f"{D}/juegos/proton-directo/compatibilitytool.vdf", 0o644),
    ("steam/proton-directo/toolmanifest.vdf", f"{D}/juegos/proton-directo/toolmanifest.vdf", 0o644),
    ("steam/proton-directo/proton", f"{D}/juegos/proton-directo/proton", 0o755),
    ("lutris/wine", f"{D}/juegos/lutris/wine", 0o755),
    ("lutris/wine.yml", f"{D}/juegos/lutris/wine.yml", 0o644),
    ("lutris/system.yml", f"{D}/juegos/lutris/system.yml", 0o644),
]
# Con @P@ = <paquete>/files/archlinux (como scripts/subir-android.sh)
PLANTILLAS = [
    ("android/android-prefijo.conf", "etc/ld.so.conf.d/android-prefijo.conf"),
    ("android/firefox-android.js", f"{D}/firefox-android.js"),
]


class Salida:
    def __init__(self, path):
        modo = "w:gz" if path.endswith((".tgz", ".tar.gz")) else "w"
        self.t = tarfile.open(path, modo, format=tarfile.GNU_FORMAT)
        self.dirs = set()

    def directorio(self, nombre):
        partes = nombre.strip("/").split("/")
        for i in range(1, len(partes) + 1):
            d = "/".join(partes[:i])
            if d and d not in self.dirs:
                ti = tarfile.TarInfo(d)
                ti.type, ti.mode = tarfile.DIRTYPE, 0o755
                self.t.addfile(ti)
                self.dirs.add(d)

    def archivo(self, nombre, data, modo):
        self.directorio(os.path.dirname(nombre))
        ti = tarfile.TarInfo(nombre)
        ti.size, ti.mode, ti.mtime = len(data), modo, int(time.time())
        self.t.addfile(ti, io.BytesIO(data))


def sin_simbolos(data):
    """Los .so compilados en el teléfono traen depuración (Turnip: 80 MB → ~15 MB)."""
    if not data.startswith(b"\x7fELF"):
        return data
    with tempfile.NamedTemporaryFile() as f:
        f.write(data)
        f.flush()
        subprocess.run([STRIP, "--strip-unneeded", f.name], check=True)
        return open(f.name, "rb").read()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--prefix", required=True)
    ap.add_argument("--compilados", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    prefijo = a.prefix.rstrip("/")
    paquete = prefijo.split("/")[-3]  # /data/user/0/<paquete>/files/archlinux
    out = Salida(a.out)

    # Compilados: enlaces absolutos al prefijo del teléfono de origen → al nuevo
    origen = re.compile(r"^/data/(?:user/0|data)/[^/]+/files/archlinux")
    with tarfile.open(a.compilados) as t:
        for m in t:
            m = m.replace(uid=0, gid=0, uname="", gname="", deep=False)
            nombre = m.name.removeprefix("./")
            if not nombre or SALTAR.search(nombre):
                continue
            if nombre.startswith("home/user/"):
                nombre = "usr/local/" + nombre[len("home/user/"):]
            elif nombre.rstrip("/") == "home/user":
                continue
            m.name = nombre
            if m.isdir():
                if nombre.rstrip("/") not in out.dirs:
                    out.directorio(nombre)
                continue
            out.directorio(os.path.dirname(nombre))
            if m.issym():
                destino = origen.sub(prefijo, m.linkname).replace(VIEJO.decode(), NUEVO.decode())
                out.t.addfile(m.replace(linkname=destino, deep=False))
            elif m.isfile():
                data = sin_simbolos(t.extractfile(m).read()).replace(VIEJO, NUEVO)
                m.size = len(data)
                out.t.addfile(m, io.BytesIO(data))

    listas = [(f"apk/{f}", f"{D}/{f}", 0o644)
              for f in sorted(os.listdir(os.path.join(RAIZ, "apk"))) if f.startswith("paquetes-")]
    escritorios = []
    for d, _, fs in os.walk(os.path.join(RAIZ, "escritorios")):
        for f in sorted(fs):
            rel = os.path.relpath(os.path.join(d, f), RAIZ)
            if os.path.dirname(rel) == "escritorios" and f != "orden":
                continue  # sesion-android y autostart-android van a /usr/local/bin
            modo = 0o755 if os.access(os.path.join(RAIZ, rel), os.X_OK) else 0o644
            escritorios.append((rel, f"{D}/{rel}", modo))
    for src, dst, modo in ARCHIVOS + listas + escritorios:
        out.archivo(dst, open(os.path.join(RAIZ, src), "rb").read(), modo)
    for src, dst in PLANTILLAS:
        texto = open(os.path.join(RAIZ, src)).read().replace("@P@", f"{paquete}/files/archlinux")
        out.archivo(dst, texto.encode(), 0o644)
    # Enlace simbólico de retrocompatibilidad para scripts o configuraciones previas
    out.directorio("usr/local/share")
    ti = tarfile.TarInfo("usr/local/share/arch-android")
    ti.type = tarfile.SYMTYPE
    ti.linkname = "linux-android"
    ti.mode = 0o777
    ti.mtime = int(time.time())
    out.t.addfile(ti)
    out.t.close()


if __name__ == "__main__":
    main()
