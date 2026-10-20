#!/usr/bin/env python3
# Limpia lo que en Linux borraría un reinicio: /dev/shm (y los objetos SysV
# emulados de la glibc en /dev/shm/.sysv) es una carpeta en disco y sobrevive
# a cerrar la app y al reinicio del teléfono; Steam deja 25 MB por cada
# u<uid>-Shm_* sin borrar. Y sockets sway-ipc.* de sways muertos en /run/user.
# Se borra solo lo que no tiene abierto ni mapeado ningún proceso vivo y que no
# se tocó desde que arrancó la sesión (el proceso más viejo de la app): así no
# choca con lo que se crea mientras corre (Steam arranca a la vez que esto).
# Corre al arrancar sway (config); a mano: python limpiar-tmp.py [-n] (-n: solo mostrar).
import os
import sys

seco = '-n' in sys.argv


def procesos():
    for p in os.listdir('/proc'):
        if p.isdigit():
            yield p


def inicio_sesion():
    tck = os.sysconf('SC_CLK_TCK')
    btime = next(int(l.split()[1]) for l in open('/proc/stat') if l.startswith('btime'))
    mas_viejo = None
    for p in procesos():
        try:
            campos = open(f'/proc/{p}/stat').read().rsplit(')', 1)[1].split()
        except OSError:
            continue
        t = int(campos[19])  # starttime (campo 22; se cortó pid y comm)
        mas_viejo = t if mas_viejo is None else min(mas_viejo, t)
    return btime + mas_viejo / tck


def inodos_en_uso():
    vivos = set()
    for p in procesos():
        try:
            for fd in os.listdir(f'/proc/{p}/fd'):
                try:
                    st = os.stat(f'/proc/{p}/fd/{fd}')
                    vivos.add((st.st_dev, st.st_ino))
                except OSError:
                    pass
            for l in open(f'/proc/{p}/maps'):
                c = l.split(maxsplit=5)
                if len(c) == 6 and c[4] != '0':
                    vivos.add(('maps', int(c[4])))
        except OSError:
            pass
    return vivos


def borrar(ruta, motivo):
    print(('borraría ' if seco else 'borro ') + ruta + f' ({motivo})')
    if not seco:
        try:
            os.unlink(ruta)
        except OSError as e:
            print(f'  no se pudo: {e}')


sesion = inicio_sesion()
vivos = inodos_en_uso()
libres = 0


def viejo_y_libre(ruta):
    st = os.lstat(ruta)
    return (st.st_mtime < sesion and (st.st_dev, st.st_ino) not in vivos
            and ('maps', st.st_ino) not in vivos), st


for d in ('/dev/shm', '/dev/shm/.sysv'):
    try:
        nombres = os.listdir(d)
    except OSError:
        continue
    for n in nombres:
        ruta = f'{d}/{n}'
        if n == 'ids' or os.path.islink(ruta) or os.path.isdir(ruta):
            continue  # ids: contador de la emulación SysV; claves y carpetas: abajo
        try:
            ok, st = viejo_y_libre(ruta)
        except OSError:
            continue
        if ok:
            libres += st.st_blocks * 512
            borrar(ruta, 'de una sesión anterior, sin uso')

# semk.<clave>/shmk.<clave> -> "<id>": si el objeto ya no está, la clave sobra
try:
    for n in os.listdir('/dev/shm/.sysv'):
        if n.startswith(('semk.', 'shmk.')):
            ruta = f'/dev/shm/.sysv/{n}'
            objeto = f'/dev/shm/.sysv/{n[:3]}.{os.readlink(ruta)}'
            if not os.path.exists(objeto) or (seco and viejo_y_libre(objeto)[0]):
                borrar(ruta, 'clave de un objeto borrado')
except OSError:
    pass

# sway-ipc.<uid>.<pid>.sock de sways que ya no corren
run = os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}')
try:
    for n in os.listdir(run):
        c = n.split('.')
        if n.startswith('sway-ipc.') and n.endswith('.sock') and len(c) == 4:
            try:
                comm = open(f'/proc/{c[2]}/comm').read().strip()
            except OSError:
                comm = ''
            if comm != 'sway':
                borrar(f'{run}/{n}', 'sway muerto')
except OSError:
    pass

print(f'{libres / 2**20:.0f} MB {"a liberar" if seco else "liberados"}')
