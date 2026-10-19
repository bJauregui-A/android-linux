#!/usr/bin/python
# ¿Sirve pidfd_getfd entre procesos de la app? Toma los sockets del pid dado
# e imprime sus direcciones (lo que necesita un lsof sin /proc/net).
import ctypes, os, socket, sys

libc = ctypes.CDLL(None, use_errno=True)
SYS_pidfd_getfd = 438

pid = int(sys.argv[1])
pfd = os.pidfd_open(pid)
for fd in os.listdir(f"/proc/{pid}/fd"):
    try:
        if not os.readlink(f"/proc/{pid}/fd/{fd}").startswith("socket:"):
            continue
    except OSError as e:
        print("readlink", fd, e)
        continue
    nfd = libc.syscall(SYS_pidfd_getfd, pfd, int(fd), 0)
    if nfd < 0:
        print("pidfd_getfd", fd, os.strerror(ctypes.get_errno()))
        continue
    s = socket.socket(fileno=nfd)
    try:
        print(fd, s.family.name, s.type.name, s.getsockname(), s.getpeername() if s.type == socket.SOCK_STREAM else "")
    except OSError as e:
        print(fd, s.family.name, "sin par:", e)
    s.detach()
    os.close(nfd)
