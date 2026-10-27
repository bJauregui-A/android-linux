package dev.ben4shot.glibcprueba;

// Otra ranura de servidor X11 (proceso :x11c): mismo código, su propio socket, lock y log.
public class ServicioX11C extends ServicioX11 {
    @Override
    String ranura() {
        return "c";
    }
}
