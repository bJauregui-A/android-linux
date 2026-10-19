#!/usr/bin/python
# /usr/bin/lsof mínimo para Steam (steam/instalar-steam.sh lo instala; el paquete
# lsof de Arch se quita: no sirve aquí). Steam valida quién se conecta a su
# websocket con `lsof -P -F upnR -i TCP@127.0.0.1:<puerto>`, y Android no deja
# a las apps leer /proc/net/tcp. Como todos los procesos son de la misma app
# (mismo uid), se copia cada socket con pidfd_getfd y se le pregunta su
# dirección. Solo entiende -i [TCP|UDP][@host][:puerto]; -F, -P y -n se aceptan.
import ctypes, os, socket, sys

SYS_pidfd_getfd = 438
libc = ctypes.CDLL(None, use_errno=True)


def uso():
    print("lsof (glibc-prueba): solo -i [TCP|UDP][@host][:puerto] [-F campos] [-P] [-n]", file=sys.stderr)
    sys.exit(1)


args = sys.argv[1:]
campos = None
numerico_host = False
filtro = None
i = 0
while i < len(args):
    a = args[i]
    if a == "-F":
        campos = args[i + 1] if i + 1 < len(args) and not args[i + 1].startswith("-") else ""
        i += 1 if campos else 0
    elif a.startswith("-F"):
        campos = a[2:]
    elif a in ("-P", "-n", "-nP", "-Pn"):
        numerico_host = numerico_host or "n" in a
    elif a == "-i":
        filtro = args[i + 1] if i + 1 < len(args) and not args[i + 1].startswith("-") else ""
        i += 1 if filtro else 0
    elif a.startswith("-i"):
        filtro = a[2:]
    else:
        uso()
    i += 1
if filtro is None:
    uso()

# [46][TCP|UDP][@host][:puerto]
proto = None
host = None
puerto = None
f = filtro.lstrip("46")
for p in ("TCP", "UDP"):
    if f.upper().startswith(p):
        proto, f = p, f[3:]
if f.startswith("@"):
    f = f[1:]
    if f.startswith("["):
        host, _, f = f[1:].partition("]")
    else:
        host, _, f = f.partition(":")
        f = ":" + f if f else ""
if f.startswith(":"):
    puerto = int(f[1:])
ip_host = socket.gethostbyname(host) if host else None


def nombre(addr):
    h, p = addr[0], addr[1]
    if not numerico_host and h in ("127.0.0.1", "::1"):
        h = "localhost"
    elif ":" in h:
        h = "[" + h + "]"
    return f"{h}:{p}"


def coincide(addr):
    if addr is None or len(addr) < 2:
        return False
    if ip_host and addr[0] not in (ip_host, "::ffff:" + ip_host):
        return False
    return puerto is None or addr[1] == puerto


propio = os.getpid()
salida = []
for d in os.listdir("/proc"):
    if not d.isdigit() or int(d) == propio:
        continue
    pid = int(d)
    try:
        fds = os.listdir(f"/proc/{pid}/fd")
        pfd = os.pidfd_open(pid)
    except OSError:
        continue
    hallados = []
    for fd in fds:
        try:
            if not os.readlink(f"/proc/{pid}/fd/{fd}").startswith("socket:"):
                continue
        except OSError:
            continue
        nfd = libc.syscall(SYS_pidfd_getfd, pfd, int(fd), 0)
        if nfd < 0:
            continue
        s = socket.socket(fileno=nfd)
        try:
            if s.family not in (socket.AF_INET, socket.AF_INET6):
                continue
            tipo = "TCP" if s.type == socket.SOCK_STREAM else "UDP"
            if proto and tipo != proto:
                continue
            local = s.getsockname()
            try:
                par = s.getpeername()
            except OSError:
                par = None
            if coincide(local) or coincide(par):
                n = nombre(local) + ("->" + nombre(par) if par else "")
                hallados.append((int(fd), n))
        finally:
            s.detach()
            os.close(nfd)
    os.close(pfd)
    if hallados:
        st = os.stat(f"/proc/{pid}")
        with open(f"/proc/{pid}/stat") as e:
            ppid = int(e.read().rsplit(")", 1)[1].split()[1])
        salida.append((pid, ppid, st.st_uid, sorted(hallados)))

if not salida:
    sys.exit(1)
for pid, ppid, uid, hallados in salida:
    if campos is not None:
        print(f"p{pid}")
        if "R" in campos:
            print(f"R{ppid}")
        if "u" in campos:
            print(f"u{uid}")
        for fd, n in hallados:
            print(f"f{fd}")
            if "n" in campos:
                print(f"n{n}")
    else:
        for fd, n in hallados:
            print(f"pid {pid} ppid {ppid} uid {uid} fd {fd} {n}")
