package dev.ben4shot.glibcprueba;

import java.util.ArrayList;
import java.util.List;

// Qué instancia usa cada servidor X11. Cada servidor vive en su propio proceso Android (ServicioX11, ServicioX11B...),
// así que hay un número fijo de ranuras; la instancia conserva la suya mientras no se cierre.
final class RanurasX11 {
    private final String[] duenos;
    private final List<String> orden = new ArrayList<>();   // por antigüedad de asignación

    RanurasX11(int cantidad) {
        duenos = new String[cantidad];
    }

    synchronized int de(String instancia) {
        for (int i = 0; i < duenos.length; i++) {
            if (instancia.equals(duenos[i])) return i;
        }
        return -1;
    }

    // Quién tiene la ranura, o null si está libre.
    synchronized String dueno(int ranura) {
        return duenos[ranura];
    }

    // La ranura que ya tenía, o la primera libre; -1 si están todas ocupadas.
    synchronized int asignar(String instancia) {
        int actual = de(instancia);
        if (actual >= 0) return actual;
        for (int i = 0; i < duenos.length; i++) {
            if (duenos[i] == null) {
                duenos[i] = instancia;
                orden.add(instancia);
                return i;
            }
        }
        return -1;
    }

    synchronized void liberar(String instancia) {
        int i = de(instancia);
        if (i < 0) return;
        duenos[i] = null;
        orden.remove(instancia);
    }

    // La instancia que lleva más tiempo con ranura, sin contar a `excepto`; null si no hay otra.
    synchronized String masAntiguaExcepto(String excepto) {
        for (String id : orden) {
            if (!id.equals(excepto)) return id;
        }
        return null;
    }
}
