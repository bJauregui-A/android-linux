#!/usr/bin/env python3
"""Arma un prefijo base de Debian ARM64 (bookworm) con dpkg y apt listos para usar sin root.

Descarga los paquetes esenciales de los repositorios oficiales de Debian, resuelve
dependencias y genera un tarball base con:
  - dpkg y apt configurados para correr como usuario sin privilegios (--force-not-root)
  - glibc propia inyectada en /usr/lib y /usr/lib/aarch64-linux-gnu
  - base de datos local de dpkg (/var/lib/dpkg/status y /var/lib/dpkg/info/*.list)
  - enlaces duros convertidos en copias (Android no permite enlaces duros en /data)
  - enlaces simbólicos absolutos adaptados al prefijo de la app
  - configuración de APT (/etc/apt/apt.conf.d/99android) y repositorios oficiales

Uso: bootstrap-debian.py --prefix /data/user/0/<app>/files/instancias/<id>
                        --glibc <salida/usr/lib>
                        --out base-debian.tar
"""
import argparse
import hashlib
import io
import os
import re
import struct
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.request
import lzma
import gzip

MIRROR = "http://deb.debian.org/debian"
SUITE = "bookworm"
ARCH = "arm64"

# /usr unificado como Debian (usrmerge): estas carpetas son enlaces a su equivalente en /usr
USR_UNIFICADO = {"bin": "usr/bin", "sbin": "usr/sbin", "lib": "usr/lib"}

# Archivos que escribe el bootstrap y que un paquete también trae: queda el nuestro
ARCHIVOS_PROPIOS = ["etc/ld.so.conf"]

# Carpetas de Android que la glibc no traduce
PASSTHROUGH = {"proc", "sys", "dev", "data", "system", "apex", "vendor", "product",
               "odm", "system_ext", "storage", "sdcard", "linkerconfig"}

LDCONFIG = b"""#!/bin/sh
# Android: el ldconfig es estatico o innecesario; la glibc propia no usa /etc/ld.so.cache.
exit 0
"""

POLICY_RCD = b"""#!/bin/sh
# Evita que dpkg/apt intente iniciar demonios init/systemd en Android.
exit 101
"""

SUDO_WRAPPER = b"""#!/bin/bash
# Wrapper de sudo con GLIBC_FAKEROOT para Debian sin root
export GLIBC_FAKEROOT=1
while [ $# -gt 0 ]; do
    case "$1" in
        -E|--preserve-env|-s|-i)
            shift ;;
        -u)
            shift 2 ;;
        --)
            shift; break ;;
        *=*)
            export "$1"; shift ;;
        *)
            break ;;
    esac
done
exec "$@"
"""

APT_CONF_ANDROID = b"""// Configuracion de APT para Android sin root
APT::Sandbox::User "root";
DPkg::Options {
   "--force-not-root";
   "--force-bad-path";
};
Acquire::Languages "none";
Acquire::Check-Valid-Until "false";
"""

# apt instala los recomendados (sin --no-install-recommends): estos nunca, son del sistema y no tienen cabida aquí
# (servicios, kernel, firmware, arranque).
PAQUETES_VETADOS = ["network-manager", "modemmanager", "wpasupplicant", "systemd-sysv", "plymouth", "grub*",
                    "linux-image-*", "firmware-*", "bluez", "cups", "avahi-daemon", "packagekit",
                    "unattended-upgrades", "apparmor"]
# Sin comentarios // ni #: apt los toma por un registro sin "Package". La explicación va en su campo.
APT_PREFERENCES = ("Explanation: paquetes de sistema que apt no debe instalar nunca, ni como recomendados\n"
                   f"Package: {' '.join(PAQUETES_VETADOS)}\nPin: release *\nPin-Priority: -1\n").encode()

# Nuestra glibc va encima de libc6/libc-bin: retenidos para que un apt upgrade no la pise.
PAQUETES_RETENIDOS = ["libc6", "libc-bin"]

SOURCES_LIST = b"""deb [signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb [signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] http://deb.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
deb [signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
"""

# Paquetes base esenciales para tener un sistema Debian mínimo con apt funcional
PAQUETES_OBJETIVO = [
    "base-files",
    "base-passwd",
    "bash",
    "dash",
    "coreutils",
    "diffutils",
    "findutils",
    "grep",
    "sed",
    "tar",
    "gzip",
    "xz-utils",
    "dpkg",
    "apt",
    "debian-archive-keyring",
    "gpgv",
    "gpg",
    "openssl",
    "mawk",
    "libc-bin",
    "util-linux",
    "usr-is-merged",
    "perl-base",
    "hostname"
]


def bajar(url, dest):
    if os.path.exists(dest):
        return dest
    tmp = dest + ".part"
    print(f"  ↓ {os.path.basename(dest)}", file=sys.stderr)
    req = urllib.request.Request(url, headers={"User-Agent": "Antigravity-Bootstrap/1.0"})
    with urllib.request.urlopen(req, timeout=30) as r, open(tmp, "wb") as f:
        while chunk := r.read(1 << 20):
            f.write(chunk)
    os.rename(tmp, dest)
    return dest


def leer_packages(path):
    """Parsea el Packages.xz de Debian y devuelve {nombre: {campos}}."""
    pkgs = {}
    with lzma.open(path, "rt", encoding="utf-8", errors="replace") as f:
        bloque = {}
        for linea in f:
            linea = linea.rstrip("\r\n")
            if not linea:
                if "Package" in bloque:
                    pkgs[bloque["Package"]] = bloque
                bloque = {}
                continue
            if linea.startswith(" ") or linea.startswith("\t"):
                continue
            if ":" in linea:
                k, v = linea.split(":", 1)
                bloque[k.strip()] = v.strip()
        if "Package" in bloque:
            pkgs[bloque["Package"]] = bloque
    return pkgs


def resolver_dependencias(objetivos, todos):
    """Resuelve recursivamente dependencias para armar el conjunto mínimo."""
    seleccionados = set()
    cola = list(objetivos)
    
    # Paquetes que descartamos deliberadamente (ej: systemd, udev crudo, etc.)
    ignorar = {"systemd", "systemd-sysv", "init", "libpam-systemd", "sensible-utils"}

    while cola:
        pkg_nom = cola.pop(0)
        if pkg_nom in seleccionados or pkg_nom in ignorar:
            continue
        if pkg_nom not in todos:
            print(f"  [!] Aviso: paquete '{pkg_nom}' no encontrado en Packages", file=sys.stderr)
            continue
        
        seleccionados.add(pkg_nom)
        p = todos[pkg_nom]
        
        deps_str = p.get("Pre-Depends", "") + ", " + p.get("Depends", "")
        for dep in deps_str.split(","):
            dep = dep.strip()
            if not dep:
                continue
            # Tomar la primera alternativa si hay 'pkgA | pkgB'
            dep = dep.split("|")[0].strip()
            # Quitar versiones (>= 1.2.3)
            nom = re.split(r"[\s\(<>=]", dep)[0].strip()
            if nom and nom not in seleccionados and nom not in ignorar:
                cola.append(nom)

    return seleccionados


def enlace(destino, prefijo):
    """Adapta un enlace simbólico absoluto al prefijo de Android si corresponde."""
    if not destino.startswith("/"):
        return destino
    raiz = destino.lstrip("/").split("/")[0]
    if raiz in PASSTHROUGH or destino.startswith(prefijo):
        return destino
    return prefijo + destino


# update-alternatives falso: solo anota "<enlace> <destino>" de cada --install y --slave.
ALTERNATIVAS_FALSO = """#!/bin/sh
while [ $# -gt 0 ]; do
  case $1 in --install|--slave) echo "$2 $4"; shift;; esac
  shift
done
"""


def alternativas(postinsts):
    """Los postinst de la base no corren, así que sus alternativas (which, awk, lzma...) no se registran y los
    postinst de después que hacen "if which X" se saltan en silencio. Corre cada postinst en seco, con un PATH
    que solo tiene el update-alternatives falso (no toca nada), y devuelve {enlace: destino}."""
    enlaces = {}
    with tempfile.TemporaryDirectory() as d:
        falso = os.path.join(d, "update-alternatives")
        with open(falso, "w") as f:
            f.write(ALTERNATIVAS_FALSO)
        os.chmod(falso, 0o755)
        raiz = os.path.join(d, "raiz")
        os.mkdir(raiz)
        for nom, datos in sorted(postinsts.items()):
            ruta = os.path.join(d, nom + ".postinst")
            with open(ruta, "wb") as f:
                f.write(datos)
            r = subprocess.run(["/bin/sh", ruta, "configure"], env={"PATH": d, "DPKG_ROOT": raiz},
                               capture_output=True, text=True)
            for l in r.stdout.splitlines():
                m = re.fullmatch(r"(/\S+) (/\S+)", l)
                if m:
                    enlaces[m[1]] = m[2]
    return enlaces


class ExtractorDeb:
    """Extrae el archivo de datos y de control de un paquete Debian .deb (formato ar)."""
    def __init__(self, deb_path):
        self.path = deb_path
        self.data_bytes = None
        self.control_bytes = None
        self._parse()

    def _parse(self):
        with open(self.path, "rb") as f:
            magic = f.read(8)
            if magic != b"!<arch>\n":
                raise ValueError(f"{self.path} no es un archivo ar valido")
            
            while True:
                cab = f.read(60)
                if len(cab) < 60:
                    break
                nombre = cab[:16].decode("ascii", errors="replace").strip()
                size_str = cab[48:58].decode("ascii", errors="replace").strip()
                size = int(size_str)
                offset = f.tell()
                
                if nombre.startswith("data.tar"):
                    self.data_bytes = f.read(size)
                elif nombre.startswith("control.tar"):
                    self.control_bytes = f.read(size)
                else:
                    f.seek(size, io.SEEK_CUR)
                
                # En formato ar los miembros se alinean a 2 bytes
                if size % 2 == 1:
                    f.seek(1, io.SEEK_CUR)


class SalidaTar:
    def __init__(self, path, reservados=()):
        """reservados: nombres que escribe el bootstrap (nuestra glibc, configuración): si un paquete trae el mismo,
        se omite y queda el nuestro."""
        self.t = tarfile.open(path, "w", format=tarfile.GNU_FORMAT)
        self.dirs = set()
        self.reservados = set(reservados)
        for enlace_, destino in USR_UNIFICADO.items():
            self._escribir_simbolico(enlace_, destino)

    @staticmethod
    def unificar(nombre):
        """bin/x -> usr/bin/x: lo que cuelga de un enlace del /usr unificado se escribe debajo de usr/."""
        for carpeta, destino in USR_UNIFICADO.items():
            if nombre == carpeta or nombre.startswith(carpeta + "/"):
                return destino + nombre[len(carpeta):]
        return nombre

    def directorio(self, nombre, modo=0o755):
        partes = self.unificar(nombre.strip("/")).split("/")
        for i in range(1, len(partes) + 1):
            d = "/".join(partes[:i])
            if d and d not in self.dirs:
                ti = tarfile.TarInfo(d)
                ti.type, ti.mode = tarfile.DIRTYPE, modo
                self.t.addfile(ti)
                self.dirs.add(d)

    def archivo(self, nombre, data, modo=0o644):
        nombre = self.unificar(nombre)
        self.directorio(os.path.dirname(nombre))
        ti = tarfile.TarInfo(nombre)
        ti.size, ti.mode, ti.mtime = len(data), modo, int(time.time())
        self.t.addfile(ti, io.BytesIO(data))

    def simbolico(self, nombre, destino):
        nombre = self.unificar(nombre)
        self.directorio(os.path.dirname(nombre))
        self._escribir_simbolico(nombre, destino)

    def _escribir_simbolico(self, nombre, destino):
        ti = tarfile.TarInfo(nombre)
        ti.type, ti.linkname, ti.mode, ti.mtime = tarfile.SYMTYPE, destino, 0o777, int(time.time())
        self.t.addfile(ti)

    def _destino_movido(self, nombre, nuevo, linkname):
        """Un enlace relativo que se mueve (bin/x -> usr/bin/x) o que apunta a algo que se mueve se recalcula desde
        su carpeta nueva, para que siga apuntando al mismo archivo."""
        origen = os.path.dirname(nombre)
        destino = os.path.normpath(os.path.join(origen, linkname))
        nuevo_destino = self.unificar(destino)
        if nuevo == nombre and nuevo_destino == destino:
            return linkname
        return os.path.relpath(nuevo_destino, os.path.dirname(nuevo))

    def miembro(self, m, f, prefijo):
        m = m.replace(uid=0, gid=0, uname="", gname="", deep=False)
        original = m.name.rstrip("/")
        m.name = self.unificar(original) + ("/" if m.isdir() else "")
        nombre = m.name.rstrip("/")
        self.directorio(os.path.dirname(nombre))
        if m.isdir():
            if nombre in self.dirs:
                return
            self.dirs.add(nombre)
            self.t.addfile(m)
        elif nombre in self.reservados:
            return
        elif m.issym():
            linkname = enlace(m.linkname, prefijo)
            if not linkname.startswith("/"):
                linkname = self._destino_movido(original, nombre, linkname)
            self.t.addfile(m.replace(linkname=linkname, deep=False))
        elif m.islnk():  # enlace duro -> copia regular
            data = f.read()
            m.type, m.linkname, m.size = tarfile.REGTYPE, "", len(data)
            self.t.addfile(m, io.BytesIO(data))
        else:
            self.t.addfile(m, f)


def main():
    ap = argparse.ArgumentParser(description="Bootstrap Debian ARM64 para Android")
    ap.add_argument("--prefix", required=True, help="Ruta del prefijo en el telefono")
    ap.add_argument("--glibc", required=True, help="Carpeta con glibc propia (salida/usr/lib)")
    ap.add_argument("--out", required=True, help="Archivo tar de salida")
    ap.add_argument("--cache", default=os.path.expanduser("~/.cache/glibc-prueba/debian-bookworm"))
    a = ap.parse_args()

    os.makedirs(a.cache, exist_ok=True)
    prefijo = a.prefix.rstrip("/")

    # 1. Bajar índice Packages.xz
    pkg_xz = os.path.join(a.cache, f"Packages-{SUITE}-{ARCH}.xz")
    pkg_url = f"{MIRROR}/dists/{SUITE}/main/binary-{ARCH}/Packages.xz"
    if not os.path.exists(pkg_xz) or (time.time() - os.path.getmtime(pkg_xz) > 24 * 3600):
        print(f"Descargando indice de paquetes Debian {SUITE}...", file=sys.stderr)
        bajar(pkg_url, pkg_xz)

    todos = leer_packages(pkg_xz)
    print(f"Indice cargado: {len(todos)} paquetes disponibles", file=sys.stderr)

    # 2. Resolver dependencias
    seleccionados = resolver_dependencias(PAQUETES_OBJETIVO, todos)
    print(f"Total paquetes resueltos: {len(seleccionados)}", file=sys.stderr)

    # Nuestra glibc va encima de la de los paquetes (y la configuración que escribimos, encima de la suya)
    libs = sorted(f for f in os.listdir(a.glibc)
                  if re.search(r"\.so(\.\d+)+$", f) or f.startswith("ld-linux"))
    reservados = [f"usr/lib/{f}" for f in libs] + [f"usr/lib/aarch64-linux-gnu/{f}" for f in libs] + ARCHIVOS_PROPIOS
    out = SalidaTar(a.out, reservados)

    # Estructura base de directorios FHS (bin, sbin y lib son enlaces a usr/, los crea SalidaTar)
    for d in ["usr/bin", "usr/sbin", "usr/lib",
              "usr/lib/aarch64-linux-gnu", "usr/local/bin", "usr/local/sbin",
              "etc/apt/apt.conf.d", "etc/apt/sources.list.d", "etc/dpkg/dpkg.cfg.d",
              "var/lib/dpkg/info", "var/lib/dpkg/updates", "var/log",
              "home/user", "var/lib/linux-android", "dev/shm/.sysv", "mnt", "media"]:
        out.directorio(d)
    # /tmp y /var/tmp: de root, con sticky, como en Debian (B96); la carpeta padre ya existe, con su modo
    out.directorio("tmp", 0o1777)
    out.directorio("var/tmp", 0o1777)

    # Base de datos de dpkg
    status_entries = []
    postinsts = {}

    # 3. Descargar y desempaquetar paquetes
    orden = sorted(seleccionados, key=lambda n: (n not in ["base-files", "dpkg", "dash", "bash", "coreutils"], n))

    for nom in orden:
        p = todos[nom]
        fn = p["Filename"]
        dest = os.path.join(a.cache, os.path.basename(fn))
        bajar(f"{MIRROR}/{fn}", dest)

        # Verificar checksum
        sha = hashlib.sha256(open(dest, "rb").read()).hexdigest()
        if sha != p.get("SHA256"):
            os.remove(dest)
            sys.exit(f"SHA256 no coincide para {nom}: {fn}")

        deb = ExtractorDeb(dest)
        if not deb.data_bytes:
            print(f"  [!] Aviso: {nom} no tiene data.tar", file=sys.stderr)
            continue

        archivos_instalados = []
        with tarfile.open(fileobj=io.BytesIO(deb.data_bytes), mode="r:*") as t:
            for m in t:
                nombre = m.name[2:] if m.name.startswith("./") else m.name
                if not nombre or nombre == ".":
                    continue
                m.name = nombre
                f = t.extractfile(m) if (m.isfile() or m.islnk()) else None
                out.miembro(m, f, prefijo)
                if not m.isdir():
                    archivos_instalados.append("/" + nombre)

        # Registrar en /var/lib/dpkg/info/<pkg>.list
        list_content = "\n".join(sorted(archivos_instalados)) + "\n"
        out.archivo(f"var/lib/dpkg/info/{nom}.list", list_content.encode("utf-8"))

        # Extraer control para /var/lib/dpkg/status
        if deb.control_bytes:
            with tarfile.open(fileobj=io.BytesIO(deb.control_bytes), mode="r:*") as tc:
                for cm in tc:
                    cname = cm.name[2:] if cm.name.startswith("./") else cm.name
                    if cname == "control":
                        cf = tc.extractfile(cm)
                        if cf:
                            cdata = cf.read().decode("utf-8", errors="replace")
                            # Inyectar Status: install ok installed
                            lineas = cdata.strip().splitlines()
                            nueva_entrada = []
                            status_puesto = False
                            estado = "hold" if nom in PAQUETES_RETENIDOS else "install"
                            for l in lineas:
                                nueva_entrada.append(l)
                                if l.startswith("Package:") and not status_puesto:
                                    nueva_entrada.append(f"Status: {estado} ok installed")
                                    status_puesto = True
                            if not status_puesto:
                                nueva_entrada.append(f"Status: {estado} ok installed")
                            status_entries.append("\n".join(nueva_entrada) + "\n")
                    elif cname in ["postinst", "preinst", "prerm", "postrm"]:
                        cf = tc.extractfile(cm)
                        if cf:
                            datos = cf.read()
                            out.archivo(f"var/lib/dpkg/info/{nom}.{cname}", datos, 0o755)
                            if cname == "postinst":
                                postinsts[nom] = datos

        print(f"  ✔ {nom} ({p.get('Version', '')})", file=sys.stderr)

    # 4. Escribir /var/lib/dpkg/status y available
    out.archivo("var/lib/dpkg/status", "\n".join(status_entries).encode("utf-8"))
    out.archivo("var/lib/dpkg/available", b"")

    # 5. Inyectar glibc propia encima del rootfs
    for f in libs:
        data = open(os.path.join(a.glibc, f), "rb").read()
        out.archivo(f"usr/lib/{f}", data, 0o755)
        out.archivo(f"usr/lib/aarch64-linux-gnu/{f}", data, 0o755)

    # 6. Archivos de sistema y configuraciones esenciales
    out.archivo("usr/bin/ldconfig", LDCONFIG, 0o755)
    out.archivo("usr/sbin/policy-rc.d", POLICY_RCD, 0o755)
    out.archivo("usr/local/bin/sudo", SUDO_WRAPPER, 0o755)
    out.archivo("etc/apt/apt.conf.d/99android", APT_CONF_ANDROID, 0o644)
    out.archivo("etc/apt/preferences.d/android", APT_PREFERENCES, 0o644)
    out.archivo("etc/apt/sources.list", SOURCES_LIST, 0o644)
    out.archivo("etc/resolv.conf", b"nameserver 1.1.1.1\nnameserver 8.8.8.8\n", 0o644)
    out.archivo("etc/ld.so.conf", b"/usr/lib/aarch64-linux-gnu\n/lib/aarch64-linux-gnu\n/usr/lib\n/lib\n", 0o644)
    out.archivo("etc/environment", b"LD_LIBRARY_PATH=/usr/lib/aarch64-linux-gnu:/lib/aarch64-linux-gnu:/usr/lib:/lib\nPATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\n", 0o644)

    # Enlace de la llave GPG oficial de Debian en trusted.gpg.d para verificacion de firmas en apt
    out.simbolico("etc/apt/trusted.gpg.d/debian-archive-keyring.gpg", "../../../usr/share/keyrings/debian-archive-keyring.gpg")

    # Alternativas que registrarían los postinst de la base (which, awk, lzma...), como enlaces directos al destino.
    for link, destino in sorted(alternativas(postinsts).items()):
        enlace_, destino = out.unificar(link.lstrip("/")), out.unificar(destino.lstrip("/"))
        out.simbolico(enlace_, os.path.relpath(destino, os.path.dirname(enlace_)))

    # Nuestra glibc usa --libdir=/usr/lib y busca los módulos de iconv en /usr/lib/gconv; Debian los guarda en el
    # directorio multiarch. Sin este enlace iconv() falla y el postinst de dictionaries-common rompe la instalación.
    out.simbolico("usr/lib/gconv", "aarch64-linux-gnu/gconv")

    # Stub de update-rc.d para evitar fallos de demonios init/systemd en Android
    out.archivo("usr/sbin/update-rc.d", b"#!/bin/sh\nexit 0\n", 0o755)

    # nologin -> false
    out.simbolico("usr/sbin/nologin", "../bin/false")

    out.directorio("run/sshd")

    # Usuarios y grupos estándar de Debian. El del usuario lo agrega primer-arranque.sh con el UID real.
    # Los de base-passwd (su postinst no corre aquí): sin ellos fallan los postinst de otros paquetes (exim4-config
    # pide uucp). Cada GID existe en etc/group.
    out.archivo("etc/passwd",
                b"root:x:0:0:root:/root:/bin/bash\n"
                b"daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin\n"
                b"bin:x:2:2:bin:/bin:/usr/sbin/nologin\n"
                b"sys:x:3:3:sys:/dev:/usr/sbin/nologin\n"
                b"sync:x:4:65534:sync:/bin:/bin/sync\n"
                b"games:x:5:60:games:/usr/games:/usr/sbin/nologin\n"
                b"man:x:6:12:man:/var/cache/man:/usr/sbin/nologin\n"
                b"lp:x:7:7:lp:/var/spool/lpd:/usr/sbin/nologin\n"
                b"mail:x:8:8:mail:/var/mail:/usr/sbin/nologin\n"
                b"news:x:9:9:news:/var/spool/news:/usr/sbin/nologin\n"
                b"uucp:x:10:10:uucp:/var/spool/uucp:/usr/sbin/nologin\n"
                b"proxy:x:13:13:proxy:/bin:/usr/sbin/nologin\n"
                b"www-data:x:33:33:www-data:/var/www:/usr/sbin/nologin\n"
                b"backup:x:34:34:backup:/var/backups:/usr/sbin/nologin\n"
                b"list:x:38:38:Mailing List Manager:/var/list:/usr/sbin/nologin\n"
                b"irc:x:39:39:ircd:/run/ircd:/usr/sbin/nologin\n"
                b"_apt:x:42:65534::/nonexistent:/usr/sbin/nologin\n"
                b"nobody:x:65534:65534:nobody:/nonexistent:/usr/sbin/nologin\n"
                b"sshd:x:100:65534::/run/sshd:/usr/sbin/nologin\n", 0o644)
    out.archivo("etc/group",
                b"root:x:0:\n"
                b"daemon:x:1:\n"
                b"bin:x:2:\n"
                b"sys:x:3:\n"
                b"adm:x:4:\n"
                b"tty:x:5:\n"
                b"disk:x:6:\n"
                b"lp:x:7:\n"
                b"mail:x:8:\n"
                b"news:x:9:\n"
                b"uucp:x:10:\n"
                b"man:x:12:\n"
                b"proxy:x:13:\n"
                b"kmem:x:15:\n"
                b"dialout:x:20:\n"
                b"fax:x:21:\n"
                b"voice:x:22:\n"
                b"cdrom:x:24:\n"
                b"floppy:x:25:\n"
                b"tape:x:26:\n"
                b"sudo:x:27:\n"
                b"audio:x:29:\n"
                b"dip:x:30:\n"
                b"www-data:x:33:\n"
                b"backup:x:34:\n"
                b"operator:x:37:\n"
                b"list:x:38:\n"
                b"irc:x:39:\n"
                b"src:x:40:\n"
                b"gnats:x:41:\n"
                b"shadow:x:42:\n"
                b"utmp:x:43:\n"
                b"video:x:44:\n"
                b"sasl:x:45:\n"
                b"plugdev:x:46:\n"
                b"staff:x:50:\n"
                b"games:x:60:\n"
                b"users:x:100:\n"
                b"_ssh:x:101:\n"
                b"ssh:x:102:\n"
                b"nogroup:x:65534:\n", 0o644)

    out.t.close()
    tam_mb = os.path.getsize(a.out) / (1024 * 1024)
    print(f"\nRootfs Debian ARM64 generado exitosamente: {a.out} ({tam_mb:.1f} MB)", file=sys.stderr)


if __name__ == "__main__":
    main()
