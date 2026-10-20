# Núcleos según el foco (SM6375: 0-5 lentos, 6-7 rápidos). Cada proceso pertenece a la
# ventana más cercana hacia arriba en su árbol (el pid que sway da a la ventana): la enfocada
# usa los 8 núcleos y las demás 0-5, así los rápidos quedan para la que se usa. Los renderers
# de Steam (hilo "Compositor": su hilo principal corre el JS de la interfaz al 80-100 %) van a
# 6-7 cuando Steam está enfocado: las portadas cargan antes. Cada `reaper` de Steam (el juego con
# su Wine: wineserver nunca tiene ventana) cuenta como una app aparte, enfocada si la ventana
# enfocada cuelga de él. Lo que no cuelga de nada (Xwayland, audio, waybar) vuelve a 0-7; el
# proceso Android de la app (padre de sway) no se toca. Se repasa cada 3 s: los procesos nuevos
# heredan la afinidad del padre y Android la reescribe al pasar la app a primer plano.
import os
import threading
import time

import i3ipc

SWAY = int(os.environ["SWAYSOCK"].rsplit(".", 2)[1])

TODOS, LENTOS, RAPIDOS = set(range(8)), set(range(6)), {6, 7}

estado = {"foco": None, "ventanas": set()}
cerrojo = threading.Lock()


def leer_procesos():
    padres, nombres = {}, {}
    for d in os.listdir("/proc"):
        if not d.isdigit():
            continue
        try:
            with open(f"/proc/{d}/stat") as f:
                cabeza, resto = f.read().rsplit(")", 1)
        except OSError:
            continue
        padres[int(d)] = int(resto.split()[1])
        nombres[int(d)] = cabeza.split("(", 1)[1]
    return padres, nombres


def ancestros(pid, padres):
    while pid > 1:
        yield pid
        pid = padres.get(pid, 0)


def dueno_de(pid, padres, duenos):
    for a in ancestros(pid, padres):
        if a in duenos:
            return a
    return None


def hilos(pid):
    try:
        return [int(t) for t in os.listdir(f"/proc/{pid}/task")]
    except OSError:
        return []


def es_renderer_steam(pid):
    try:
        with open(f"/proc/{pid}/comm") as f:
            if f.read().strip() != "steamwebhelper":
                return False
    except OSError:
        return False
    for t in hilos(pid):
        try:
            with open(f"/proc/{pid}/task/{t}/comm") as f:
                if f.read().strip() == "Compositor":
                    return True
        except OSError:
            pass
    return False


def fijar(pid, nucleos):
    for t in hilos(pid):
        try:
            if os.sched_getaffinity(t) != nucleos:
                os.sched_setaffinity(t, nucleos)
        except OSError:
            pass


def repartir():
    with cerrojo:
        foco, ventanas = estado["foco"], set(estado["ventanas"])
    if foco is None:
        return
    padres, nombres = leer_procesos()
    reapers = {p for p, n in nombres.items() if n == "reaper"}
    duenos = ventanas | reapers
    del_foco = set(ancestros(foco, padres))
    enfocados = {foco} | (reapers & del_foco)
    intocables = set(ancestros(padres.get(SWAY, 0), padres))
    for pid in padres:
        d = dueno_de(pid, padres, duenos)
        if d is None:
            if pid not in intocables:
                fijar(pid, TODOS)
        elif d not in enfocados:
            fijar(pid, LENTOS)
        elif es_renderer_steam(pid):
            fijar(pid, RAPIDOS)
        else:
            fijar(pid, TODOS)


def leer_arbol(sway, _evento=None):
    hojas = sway.get_tree().leaves()
    with cerrojo:
        estado["ventanas"] = {v.pid for v in hojas if v.pid}
        for v in hojas:
            if v.focused and v.pid:
                estado["foco"] = v.pid
    repartir()


def repaso():
    while True:
        time.sleep(3)
        repartir()


sway = i3ipc.Connection()
leer_arbol(sway)
threading.Thread(target=repaso, daemon=True).start()
for e in (i3ipc.Event.WINDOW_FOCUS, i3ipc.Event.WINDOW_NEW, i3ipc.Event.WINDOW_CLOSE):
    sway.on(e, leer_arbol)
sway.main()
