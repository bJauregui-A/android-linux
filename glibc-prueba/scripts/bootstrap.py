#!/usr/bin/env python3
"""Arma un prefijo de Arch Linux ARM con pacman listo para usar dentro de la app.

Resuelve dependencias con las bases de datos del repositorio, baja los paquetes
(verifica sha256) y escribe un tar con:
  - el contenido de los paquetes (enlaces duros -> copias, enlaces simbólicos
    absolutos -> con el prefijo del teléfono, como hace symlinkat en la glibc)
  - la base de datos local de pacman (var/lib/pacman/local), así pacman sabe
    qué está instalado
  - la glibc propia encima de la de Arch (protegida con IgnorePkg/NoExtract)
  - pacman.conf ajustado (sin CheckSpace, sin DownloadUser, DisableSandbox)

No ejecuta los scripts de instalación (.INSTALL): eso se hace en el teléfono.

Uso: bootstrap.py --prefix /data/user/0/<app>/files/archlinux --glibc <salida/usr/lib>
                  --out rootfs.tar [paquetes...]   (por defecto: base)
"""
import argparse
import hashlib
import io
import os
import re
import sys
import tarfile
import time
import urllib.request

MIRROR = "http://mirror.archlinuxarm.org/aarch64"
REPOS = ["core", "extra", "alarm"]
# Carpetas de Android que la glibc no traduce (igual que android-path.c).
PASSTHROUGH = {"proc", "sys", "dev", "data", "system", "apex", "vendor", "product",
               "odm", "system_ext", "storage", "sdcard", "linkerconfig"}
META = {".PKGINFO", ".BUILDINFO", ".MTREE", ".INSTALL", ".CHANGELOG"}
LDCONFIG = b"""#!/usr/bin/bash
# Android: el ldconfig de Arch es estatico (no se puede ejecutar desde los datos
# de la app) y la glibc propia no usa /etc/ld.so.cache.  No hace nada.
exit 0
"""
PACMAN_XFER = b"""#!/bin/sh
# Wrapper de descarga para pacman:
# Mapea las bases de datos de holo-core y holo-extra a core.db y extra.db del servidor SteamOS.
url="$1"
out="$2"
case "$url" in
    */holo-core.db*)     url="${url%holo-core.db*}core.db${url#*holo-core.db}" ;;
    */holo-extra.db*)    url="${url%holo-extra.db*}extra.db${url#*holo-extra.db}" ;;
    */holo-core.db.sig*) url="${url%holo-core.db.sig*}core.db.sig${url#*holo-core.db.sig}" ;;
    */holo-extra.db.sig*) url="${url%holo-extra.db.sig*}extra.db.sig${url#*holo-extra.db.sig}" ;;
    */holo-core.files*)  url="${url%holo-core.files*}core.files${url#*holo-core.files}" ;;
    */holo-extra.files*) url="${url%holo-extra.files*}extra.files${url#*holo-extra.files}" ;;
esac
exec /usr/bin/curl -q -s -f -L -C - --connect-timeout 15 -o "$out" "$url"
"""


def bajar(url, dest):
    if os.path.exists(dest):
        return dest
    tmp = dest + ".part"
    with urllib.request.urlopen(url) as r, open(tmp, "wb") as f:
        while chunk := r.read(1 << 20):
            f.write(chunk)
    os.rename(tmp, dest)
    return dest


def leer_db(path, repo):
    """Devuelve {nombre: campos} de una base de datos de repositorio."""
    pkgs = {}
    with tarfile.open(path, "r:*") as t:
        for m in t:
            if not m.isfile():
                continue
            campos, clave = {}, None
            for linea in t.extractfile(m).read().decode().splitlines():
                if linea.startswith("%") and linea.endswith("%"):
                    clave = linea.strip("%")
                    campos.setdefault(clave, [])
                elif linea and clave:
                    campos[clave].append(linea)
            if "NAME" in campos:
                nombre = campos["NAME"][0]
                p = pkgs.setdefault(nombre, {"repo": repo})
                p.update(campos)
            else:  # depends/files en archivo aparte (formato viejo)
                nombre = m.name.split("/")[0].rsplit("-", 2)[0]
                pkgs.setdefault(nombre, {"repo": repo}).update(campos)
    return pkgs


def nombre_dep(dep):
    return re.split(r"[<>=]", dep, maxsplit=1)[0]


def resolver(objetivos, todos, grupos):
    proveedores = {}
    for nombre, p in todos.items():
        for prov in p.get("PROVIDES", []):
            proveedores.setdefault(nombre_dep(prov), []).append(nombre)

    elegidos, motivo, pendientes = {}, {}, []
    for o in objetivos:
        if o in todos:
            pendientes.append((o, True))
        elif o in grupos:
            pendientes += [(n, True) for n in sorted(grupos[o])]
        else:
            sys.exit(f"no existe el paquete o grupo: {o}")
    while pendientes:
        dep, explicito = pendientes.pop()
        n = nombre_dep(dep)
        if n not in todos:
            cands = proveedores.get(n)
            if not cands:
                sys.exit(f"nadie provee: {dep}")
            ya = [c for c in cands if c in elegidos]
            n = ya[0] if ya else cands[0]
        if n in elegidos:
            motivo[n] = motivo[n] or explicito
            continue
        elegidos[n] = todos[n]
        motivo[n] = explicito
        pendientes += [(d, False) for d in todos[n].get("DEPENDS", [])]
    return elegidos, motivo


def pkginfo(data):
    info = {}
    for linea in data.decode().splitlines():
        if " = " in linea and not linea.startswith("#"):
            k, v = linea.split(" = ", 1)
            info.setdefault(k, []).append(v)
    return info


def desc_local(info, explicito, validacion):
    campos = [
        ("NAME", info.get("pkgname")), ("VERSION", info.get("pkgver")),
        ("BASE", info.get("pkgbase")), ("DESC", info.get("pkgdesc")),
        ("URL", info.get("url")), ("ARCH", info.get("arch")),
        ("BUILDDATE", info.get("builddate")), ("INSTALLDATE", [str(int(time.time()))]),
        ("PACKAGER", info.get("packager")), ("SIZE", info.get("size")),
        ("REASON", None if explicito else ["1"]), ("LICENSE", info.get("license")),
        ("VALIDATION", [validacion]), ("REPLACES", info.get("replaces")),
        ("DEPENDS", info.get("depend")), ("OPTDEPENDS", info.get("optdepend")),
        ("CONFLICTS", info.get("conflict")), ("PROVIDES", info.get("provides")),
        ("XDATA", info.get("xdata")),
    ]
    return "".join(f"%{k}%\n" + "".join(v + "\n" for v in vals) + "\n"
                   for k, vals in campos if vals)


def enlace(destino, prefijo):
    if not destino.startswith("/"):
        return destino
    primero = destino.lstrip("/").split("/", 1)[0]
    if primero in PASSTHROUGH and not destino.startswith("/dev/shm"):
        return destino
    return prefijo + destino


class Salida:
    def __init__(self, path):
        self.t = tarfile.open(path, "w", format=tarfile.GNU_FORMAT)
        self.dirs = set()

    def directorio(self, nombre, modo=0o755):
        partes = nombre.strip("/").split("/")
        for i in range(1, len(partes) + 1):
            d = "/".join(partes[:i])
            if d and d not in self.dirs:
                ti = tarfile.TarInfo(d)
                ti.type, ti.mode = tarfile.DIRTYPE, modo
                self.t.addfile(ti)
                self.dirs.add(d)

    def archivo(self, nombre, data, modo=0o644):
        self.directorio(os.path.dirname(nombre))
        ti = tarfile.TarInfo(nombre)
        ti.size, ti.mode, ti.mtime = len(data), modo, int(time.time())
        self.t.addfile(ti, io.BytesIO(data))

    def miembro(self, m, f, prefijo):
        m = m.replace(uid=0, gid=0, uname="", gname="", deep=False)
        self.directorio(os.path.dirname(m.name.rstrip("/")))
        if m.isdir():
            if m.name.rstrip("/") in self.dirs:
                return
            self.dirs.add(m.name.rstrip("/"))
            self.t.addfile(m)
        elif m.issym():
            self.t.addfile(m.replace(linkname=enlace(m.linkname, prefijo), deep=False))
        elif m.islnk():  # enlace duro -> copia
            data = f.read()
            m.type, m.linkname, m.size = tarfile.REGTYPE, "", len(data)
            self.t.addfile(m, io.BytesIO(data))
        else:
            self.t.addfile(m, f)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--prefix", required=True, help="ruta del prefijo en el teléfono")
    ap.add_argument("--glibc", required=True, help="carpeta con la glibc propia (salida/usr/lib)")
    ap.add_argument("--out", required=True)
    ap.add_argument("--cache", default=os.path.expanduser("~/.cache/glibc-prueba"))
    ap.add_argument("paquetes", nargs="*", default=["base"])
    a = ap.parse_args()
    os.makedirs(a.cache, exist_ok=True)
    prefijo = a.prefix.rstrip("/")

    todos, grupos = {}, {}
    for repo in REPOS:
        db = os.path.join(a.cache, f"{repo}.db")
        if os.path.exists(db) and time.time() - os.path.getmtime(db) > 6 * 3600:
            os.remove(db)
        bajar(f"{MIRROR}/{repo}/{repo}.db", db)
        for n, p in leer_db(db, repo).items():
            if n not in todos:  # gana el primer repositorio, como pacman
                todos[n] = p
                for g in p.get("GROUPS", []):
                    grupos.setdefault(g, set()).add(n)

    objetivos = a.paquetes + ["pacman", "filesystem", "archlinuxarm-keyring"]
    elegidos, motivo = resolver(objetivos, todos, grupos)
    print(f"{len(elegidos)} paquetes", file=sys.stderr)

    out = Salida(a.out)
    total = 0
    # filesystem primero: crea /bin -> usr/bin, etc. antes que el resto
    orden = sorted(elegidos, key=lambda n: (n != "filesystem", n))
    for n in orden:
        p = elegidos[n]
        fn = p["FILENAME"][0]
        path = bajar(f"{MIRROR}/{p['repo']}/{fn}", os.path.join(a.cache, fn))
        sha = hashlib.sha256(open(path, "rb").read()).hexdigest()
        if sha != p["SHA256SUM"][0]:
            os.remove(path)
            sys.exit(f"sha256 no coincide: {fn}")
        total += os.path.getsize(path)

        archivos, meta, backup = [], {}, {}
        with tarfile.open(path, "r:*") as t:
            for m in t:
                nombre = m.name[2:] if m.name.startswith("./") else m.name
                m.name = nombre
                if nombre in META:
                    meta[nombre] = t.extractfile(m).read()
                    continue
                f = t.extractfile(m) if (m.isfile() or m.islnk()) else None
                if f is not None and m.isfile():
                    data = f.read()
                    f = io.BytesIO(data)
                    backup[nombre] = hashlib.md5(data).hexdigest()
                out.miembro(m, f, prefijo)
                archivos.append(nombre + "/" if m.isdir() and not nombre.endswith("/") else nombre)

        info = pkginfo(meta[".PKGINFO"])
        local = f"var/lib/pacman/local/{n}-{info['pkgver'][0]}"
        out.archivo(f"{local}/desc", desc_local(info, motivo[n], "sha256").encode())
        files = "%FILES%\n" + "".join(x + "\n" for x in sorted(archivos)) + "\n"
        if info.get("backup"):
            files += "%BACKUP%\n" + "".join(
                f"{b}\t{backup.get(b, '')}\n" for b in info["backup"]) + "\n"
        out.archivo(f"{local}/files", files.encode())
        if ".MTREE" in meta:
            out.archivo(f"{local}/mtree", meta[".MTREE"])
        if ".INSTALL" in meta:
            out.archivo(f"{local}/install", meta[".INSTALL"])
        print(f"  {n} {info['pkgver'][0]}", file=sys.stderr)

    out.archivo("var/lib/pacman/local/ALPM_DB_VERSION", b"9\n")
    for d in ["var/lib/pacman/sync", "var/cache/pacman/pkg", "var/log", "tmp", "home/user"]:
        out.directorio(d)

    # glibc propia encima de la de Arch
    libs = sorted(f for f in os.listdir(a.glibc)
                  if re.search(r"\.so(\.\d+)+$", f) or f.startswith("ld-linux"))
    for f in libs:
        out.archivo(f"usr/lib/{f}", open(os.path.join(a.glibc, f), "rb").read(), 0o755)

    # ldconfig de Arch es estático: no se puede ejecutar (W^X) y la glibc propia
    # no usa /etc/ld.so.cache (busca directo en /usr/lib del prefijo).
    out.archivo("usr/bin/ldconfig", LDCONFIG, 0o755)
    out.archivo("usr/local/bin/pacman-xfer", PACMAN_XFER, 0o755)

    # pacman.conf: sin CheckSpace (miraría los puntos de montaje de Android),
    # sin DownloadUser (no hay setuid) y sin sandbox (landlock no está
    # permitido por el seccomp de apps).
    with tarfile.open(os.path.join(a.cache, elegidos["pacman"]["FILENAME"][0]), "r:*") as t:
        conf = t.extractfile("etc/pacman.conf").read().decode()
    conf = re.sub(r"(?m)^CheckSpace", "#CheckSpace", conf)
    conf = re.sub(r"(?m)^DownloadUser", "#DownloadUser", conf)
    conf = re.sub(r"(?m)^#?DisableSandbox.*$", "", conf)
    conf = re.sub(r"(?m)^#?HoldPkg\s*=.*$", "HoldPkg     = pacman glibc sway wlroots mesa", conf, count=1)
    conf = re.sub(r"(?m)^#?IgnorePkg\s*=.*$", "IgnorePkg   = glibc sway wlroots mesa", conf, count=1)
    conf = re.sub(r"(?m)^#?NoExtract\s*=.*$",
                  "NoExtract   = usr/bin/ldconfig " + " ".join(f"usr/lib/{f}" for f in libs),
                  conf, count=1)
    if "XferCommand" in conf:
        conf = re.sub(r"(?m)^#?XferCommand\s*=.*$", "XferCommand = /usr/local/bin/pacman-xfer %u %o", conf, count=1)
    else:
        conf = conf.replace("[options]\n", "[options]\nXferCommand = /usr/local/bin/pacman-xfer %u %o\n", 1)
    conf = conf.replace("[options]\n", "[options]\nDisableSandbox\n", 1)

    # Repositorios: holo-core y holo-extra como principales (SteamOS cloud, sin firmas de Valve),
    # y core/extra de Arch ARM con firmas requeridas incrustadas (%PGPSIG%)
    repos_holo = """[holo-core]
SigLevel = Never
Server = https://holo-packages.steamos.cloud/holo-core-aarch64-preview/mash-20251118.3/core/os/$arch

[holo-extra]
SigLevel = Never
Server = https://holo-packages.steamos.cloud/holo-core-aarch64-preview/mash-20251118.3/extra/os/$arch

"""
    conf = conf.replace("[core]\n", repos_holo + "[core]\n", 1)
    out.archivo("etc/pacman.conf", conf.encode())
    out.archivo("etc/resolv.conf", b"nameserver 1.1.1.1\nnameserver 8.8.8.8\n")
    out.t.close()
    print(f"bajado: {total / 1e6:.0f} MB -> {a.out} ({os.path.getsize(a.out) / 1e6:.0f} MB)",
          file=sys.stderr)


if __name__ == "__main__":
    main()
