package dev.ben4shot.glibcprueba;

import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.Map;

/** Reparto de IP de instancias en la subred por defecto (10.0.0.0/24); lógica pura, sin Context. */
final class AsignacionIps {
    private AsignacionIps() {}

    static String primeraLibre(Collection<String> ipsOcupadas) {
        int n = 2;
        while (ipsOcupadas.contains("10.0.0." + n)) n++;
        return "10.0.0." + n;
    }

    static Map<String, String> limpiar(Map<String, String> asignaciones, Collection<String> registradas) {
        Map<String, String> limpias = new LinkedHashMap<>();
        for (Map.Entry<String, String> e : asignaciones.entrySet()) {
            if (registradas.contains(e.getKey())) limpias.put(e.getKey(), e.getValue());
        }
        return limpias;
    }
}
