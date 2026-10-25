package dev.ben4shot.glibcprueba;

import java.util.ArrayList;
import java.util.Collection;
import java.util.List;

/** Carpetas de files/instancias/ que no corresponden a ninguna instancia registrada; lógica pura, sin Context. */
final class CarpetasInstancias {
    private CarpetasInstancias() {}

    static List<String> sueltas(Collection<String> carpetas, Collection<String> registradas) {
        List<String> sobrantes = new ArrayList<>();
        for (String carpeta : carpetas) {
            if (!registradas.contains(carpeta)) sobrantes.add(carpeta);
        }
        return sobrantes;
    }
}
