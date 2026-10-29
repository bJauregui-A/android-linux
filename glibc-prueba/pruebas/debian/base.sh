#!/usr/bin/bash
# B11: la base de Debian (scripts/bootstrap-debian.py) desempaqueta los .deb sin correr sus postinst. La alternativa
# "which" de debianutils nunca se registraba y /usr/bin/which no existía: el postinst de shared-mime-info
# ("if which update-mime-database") se saltaba la regeneración y quedaba /usr/share/mime sin mime.cache, así que
# gdk-pixbuf no reconocía ninguna imagen (sin fondo, íconos ni panel en Xfce).
# Corre en el PC, genera la base real (usa la caché de .deb):  pruebas/debian/base.sh
cd "$(dirname "$0")/../.." || exit 1
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }
d=$(mktemp -d); trap 'rm -rf "$d"' EXIT
python3 scripts/bootstrap-debian.py --prefix /data/user/0/prueba/files/debian --glibc glibc/salida/usr/lib --out "$d/base.tar" >"$d/salida" 2>&1 \
  || { echo "FALLA no se pudo generar la base"; tail -5 "$d/salida"; exit 1; }
tar -tvf "$d/base.tar" > "$d/lista"

caso "la base trae debianutils (which.debianutils)"  'grep -q " usr/bin/which.debianutils$" "$d/lista"'
caso "usr/bin/which es un enlace a which.debianutils"  'grep -qE "^l.* usr/bin/which -> (\./|/usr/bin/)?which.debianutils$" "$d/lista"'

# El problema no es solo which: la base no corre ningún postinst. Cada enlace de update-alternatives (--install y
# --slave) que piden los postinst de la base tiene que existir. Los postinst se corren en seco: PATH solo con un
# update-alternatives falso que anota los enlaces, así que no tocan nada del PC.
mkdir -p "$d/info" "$d/stub" "$d/raiz"
tar -xf "$d/base.tar" -C "$d/info" --wildcards 'var/lib/dpkg/info/*.postinst' --strip-components=4
cat > "$d/stub/update-alternatives" <<'STUB'
#!/bin/sh
while [ $# -gt 0 ]; do
  case $1 in --install|--slave) echo "$2"; shift;; esac
  shift
done
STUB
chmod +x "$d/stub/update-alternatives"
for p in "$d"/info/*.postinst; do
  DPKG_ROOT=$d/raiz PATH=$d/stub /bin/sh "$p" configure 2>/dev/null
done | grep -E '^/[^ ]+$' | sort -u > "$d/enlaces"
caso "los postinst de la base piden enlaces de alternativas"  '[ -s "$d/enlaces" ]'
while read -r l; do
  caso "alternativa $l existe en la base"  'grep -qE " ${l#/}( -> .*)?$" "$d/lista"'
done < "$d/enlaces"

# Sin --no-install-recommends entran los recomendados: la base los frena (Pin-Priority -1) para que no traigan
# servicios de sistema ni kernel/firmware, y retiene libc6 y libc-bin para que un apt upgrade no pise nuestra glibc.
tar -xOf "$d/base.tar" etc/apt/preferences.d/android > "$d/pin" 2>/dev/null
for paq in network-manager modemmanager wpasupplicant systemd-sysv plymouth 'grub\*' 'linux-image-\*' 'firmware-\*' \
           bluez cups avahi-daemon packagekit unattended-upgrades apparmor; do
  caso "preferences.d/android frena ${paq//\\/}"  'grep -E "^Package:.*(^|[ ])$paq([ ]|$)" "$d/pin" >/dev/null'
done
# apt no admite comentarios "//" en preferences (los toma como un registro sin "Package": "Invalid record in the
# preferences file"); el registro empieza por Explanation: o Package:, y cada línea es "Campo: valor".
caso "preferences.d/android: sin comentarios // ni #"  '! grep -qE "^(//|#)" "$d/pin"'
caso "preferences.d/android: todas las líneas son Campo: valor"  '! grep -vE "^(Explanation|Package|Pin|Pin-Priority): .+$" "$d/pin" | grep -q .'
caso "preferences.d/android: el registro empieza por Explanation o Package"  'head -1 "$d/pin" | grep -qE "^(Explanation|Package): "'
caso "preferences.d/android usa Pin-Priority: -1"  'grep -qx "Pin-Priority: -1" "$d/pin" && ! grep -q "Pin-Priority: [^-]" "$d/pin"'
tar -xOf "$d/base.tar" var/lib/dpkg/status > "$d/status"
for paq in libc6 libc-bin; do
  caso "$paq está retenido (hold)"  'awk -v p="$paq" "/^Package: /{n=\$2} /^Status: /{if(n==p) print \$2}" "$d/status" | grep -qx hold'
done
caso "primer-arranque.sh no usa --no-install-recommends"  '! grep -q -- "--no-install-recommends" apk/primer-arranque.sh'

# Nuestra glibc se compila con --libdir=/usr/lib y busca los módulos de iconv en /usr/lib/gconv; Debian los deja
# en /usr/lib/aarch64-linux-gnu/gconv. Sin el enlace, iconv() falla ("failed to start conversion processing") y
# el postinst de dictionaries-common (Text::Iconv) rompe la instalación de MATE y de todo lo que dependa de aspell.
caso "usr/lib/gconv enlaza a aarch64-linux-gnu/gconv"  'grep -qE "^l.* usr/lib/gconv -> (\./)?aarch64-linux-gnu/gconv$" "$d/lista"'
caso "la base trae los módulos de gconv de Debian"  'grep -qE " usr/lib/aarch64-linux-gnu/gconv/ISO8859-1\.so$" "$d/lista"'

# La base no corre ningún postinst, así que tampoco el de base-passwd: sin los usuarios de sistema estándar, el postinst
# de otros paquetes falla (exim4-config: "user uucp was not found" y arrastra exim4-base, exim4-daemon-light, bsd-mailx).
tar -xOf "$d/base.tar" etc/passwd > "$d/passwd"
tar -xOf "$d/base.tar" etc/group > "$d/group"
for u in root daemon bin sys sync games man lp mail news uucp proxy www-data backup list irc _apt nobody; do
  caso "passwd tiene el usuario de sistema $u"  'grep -q "^$u:" "$d/passwd"'
done
caso "cada GID de passwd existe en group" \
  'while IFS=: read -r u x uid gid resto; do awk -F: -v g="$gid" "\$3==g{ok=1} END{exit !ok}" "$d/group" || { echo "  gid $gid de $u no está en group"; exit 1; }; done < "$d/passwd"'
caso "los usuarios de sistema no tienen shell de login (salvo root y sync)" \
  '! awk -F: "\$1!=\"root\" && \$1!=\"sync\" && \$1!=\"sshd\" && \$7 !~ /nologin\$/" "$d/passwd" | grep -q .'

# B19: /usr unificado como en un Debian real (usrmerge): bin, sbin y lib son enlaces a usr/. Antes eran carpetas reales
# y usr/bin/bash enlazaba "al revés" a ../../bin/bash; usr-is-merged y los paquetes que asumen el /usr unificado fallaban.
. pruebas/comun/usr-unificado.sh
caso "/usr unificado: bin, sbin y lib son enlaces a /usr"  'usr_unificado "$d/lista" bin:usr/bin sbin:usr/sbin lib:usr/lib'
caso "usr/bin/bash es un archivo, no un enlace a ../../bin/bash"  'grep -qE "^-.* usr/bin/bash$" "$d/lista"'
sed -E 's/^[^ ]+ [^ ]+ +[0-9]+ [0-9-]+ [0-9:]+ //; s/ -> .*$//; s#/$##' "$d/lista" | sort | uniq -d > "$d/repetidos"
caso "el tar no repite ningún nombre"  '! [ -s "$d/repetidos" ] || { head -5 "$d/repetidos" | sed "s/^/  repetido: /"; false; }'
for f in usr/lib/ld-linux-aarch64.so.1 usr/lib/aarch64-linux-gnu/libc.so.6; do
  caso "$f es el de nuestra glibc"  '[ "$(tar -xOf "$d/base.tar" $f | sha256sum)" = "$(sha256sum < glibc/salida/usr/lib/${f##*/})" ]'
done
# Cada enlace relativo resuelve (siguiendo los demás enlaces del tar, y los absolutos desde el prefijo) a un miembro.
cat > "$d/rotos.py" <<'PY'
import posixpath, sys, tarfile
PREFIJO = sys.argv[2]
miembros = {}
for m in tarfile.open(sys.argv[1]):
    miembros[m.name.rstrip("/")] = m
def resolver(ruta, vistos=0):
    """Ruta normalizada de verdad (sin enlaces en el camino); None si cae fuera del tar."""
    partes, hechas = ruta.split("/"), ""
    for i, p in enumerate(partes):
        if p in ("", "."): continue
        if p == "..":
            hechas = posixpath.dirname(hechas); continue
        hechas = posixpath.join(hechas, p)
        m = miembros.get(hechas)
        if m is not None and m.issym():
            if vistos > 40: return None
            t = m.linkname
            if t.startswith("/"):
                t = t[len(PREFIJO):] if t.startswith(PREFIJO + "/") else None
                if t is None: return "/fuera"
                nueva = resolver(t, vistos + 1)
            else:
                nueva = resolver(posixpath.join(posixpath.dirname(hechas), t), vistos + 1)
            if nueva is None or nueva == "/fuera": return nueva
            hechas = nueva
    return hechas
rotos = 0
for n, m in miembros.items():
    if m.issym() and not m.linkname.startswith("/"):
        d = resolver(posixpath.join(posixpath.dirname(n), m.linkname))
        if d is None or (d != "/fuera" and d != "" and d not in miembros):
            print(f"  roto: {n} -> {m.linkname}"); rotos += 1
sys.exit(1 if rotos else 0)
PY
caso "ningún enlace relativo de la base queda roto"  'python3 "$d/rotos.py" "$d/base.tar" /data/user/0/prueba/files/debian'
tar -xOf "$d/base.tar" var/lib/dpkg/info/bash.list > "$d/bash.list"
caso "bash.list sigue listando /bin/bash (ruta original, como en un Debian real)"  'grep -qx "/bin/bash" "$d/bash.list"'

# B53: hostname (paquete "hostname", Essential en Debian) y los usuarios y grupos de sistema oficiales: los de passwd.master
# y group.master de base-passwd tienen que estar en etc/passwd y etc/group con el mismo UID/GID.
caso "la base trae usr/bin/hostname"  'grep -qE " usr/bin/hostname$" "$d/lista"'
tar -xOf "$d/base.tar" usr/share/base-passwd/passwd.master > "$d/passwd.master"
tar -xOf "$d/base.tar" usr/share/base-passwd/group.master > "$d/group.master"
caso "cada usuario de passwd.master está en etc/passwd con el mismo UID" \
  'faltan=$(awk -F: "NR==FNR{u[\$1]=\$3; next} !(\$1 in u) || u[\$1]!=\$3{print \$1}" "$d/passwd" "$d/passwd.master" 2>/dev/null; [ -s "$d/passwd.master" ] || echo "(sin passwd.master)"); [ -z "$faltan" ] || { echo "  faltan: $faltan"; false; }'
caso "cada grupo de group.master está en etc/group con el mismo GID" \
  'faltan=$(awk -F: "NR==FNR{u[\$1]=\$3; next} !(\$1 in u) || u[\$1]!=\$3{print \$1}" "$d/group" "$d/group.master" 2>/dev/null; [ -s "$d/group.master" ] || echo "(sin group.master)"); [ -z "$faltan" ] || { echo "  faltan: $faltan"; false; }'

echo "fallas: $fallas"
[ $fallas -eq 0 ]
