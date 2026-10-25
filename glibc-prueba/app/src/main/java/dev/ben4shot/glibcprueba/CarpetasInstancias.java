package dev.ben4shot.glibcprueba;

import java.util.ArrayList;
import java.util.Collection;
import java.util.List;

/** Carpetas de files/instancias/ que no corresponden a ninguna instancia registrada; lógica pura, sin Context. */
final class CarpetasInstancias {
    private CarpetasInstancias() {}

    /**
     * Rutas de {@code carpetas} (relativas a files/) que no están en {@code registradas}.
     * {@code registradas == null} significa que la lista no se pudo leer: entonces no se devuelve ninguna.
     */
    static List<String> sueltas(Collection<String> carpetas, Collection<String> registradas) {
        List<String> sobrantes = new ArrayList<>();
        if (registradas == null) return sobrantes;
        for (String carpeta : carpetas) {
            if (!registradas.contains(carpeta)) sobrantes.add(carpeta);
        }
        return sobrantes;
    }
}
