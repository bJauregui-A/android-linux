package dev.ben4shot.glibcprueba;

// Otra ranura de servidor X11 (proceso :x11b): mismo código, su propio socket, lock y log.
public class ServicioX11B extends ServicioX11 {
    @Override
    String ranura() {
        return "b";
    }
}
