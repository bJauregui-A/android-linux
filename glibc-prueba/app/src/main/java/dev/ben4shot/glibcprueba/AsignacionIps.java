package dev.ben4shot.glibcprueba;

import java.util.Collection;

/** Reparto de IP de instancias en la subred por defecto (10.0.0.0/24); lógica pura, sin Context. */
final class AsignacionIps {
    private AsignacionIps() {}

    static String primeraLibre(Collection<String> ipsOcupadas) {
        int n = 2;
        while (ipsOcupadas.contains("10.0.0." + n)) n++;
        return "10.0.0." + n;
    }
}
