# Opacidad como en HyDE (decoration de defaults.lua): ventana activa 0.90,
# inactivas 0.75, pantalla completa 1. sway no tiene opacidad por foco: se ajusta
# por IPC en cada cambio de foco, ventana nueva o pantalla completa.
import i3ipc

ACTIVA, INACTIVA, COMPLETA = 0.90, 0.75, 1.0


def aplicar(sway, _evento=None):
    for v in sway.get_tree().leaves():
        if v.focused:
            o = COMPLETA if v.fullscreen_mode else ACTIVA
        else:
            o = INACTIVA
        v.command(f"opacity {o}")


sway = i3ipc.Connection()
aplicar(sway)
for e in (i3ipc.Event.WINDOW_FOCUS, i3ipc.Event.WINDOW_NEW, i3ipc.Event.WINDOW_FULLSCREEN_MODE):
    sway.on(e, aplicar)
sway.main()
