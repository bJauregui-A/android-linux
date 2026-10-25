package dev.ben4shot.glibcprueba;

import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.Map;

/** Reparto de IP de instancias en la subred por defecto (10.0.0.0/24); lógica pura, sin Context. */
final class AsignacionIps {
    private AsignacionIps() {}

    static String primeraLibre(String cidr, Collection<String> ipsOcupadas) {
        String[] partes = cidr.split("/");
        long mascara = (0xFFFFFFFFL << (32 - Integer.parseInt(partes[1]))) & 0xFFFFFFFFL;
        long red = aNumero(partes[0]) & mascara;
        long difusion = red | (~mascara & 0xFFFFFFFFL);
        long n = red + 2;
        while (ipsOcupadas.contains(aTexto(n))) n++;
        if (n >= difusion) throw new IllegalStateException("Subred llena: " + cidr);
        return aTexto(n);
    }

    private static long aNumero(String ip) {
        long n = 0;
        for (String octeto : ip.split("\\.")) n = (n << 8) | Integer.parseInt(octeto);
        return n;
    }

    private static String aTexto(long n) {
        return (n >> 24 & 0xFF) + "." + (n >> 16 & 0xFF) + "." + (n >> 8 & 0xFF) + "." + (n & 0xFF);
    }

    static Map<String, String> limpiar(Map<String, String> asignaciones, Collection<String> registradas) {
        Map<String, String> limpias = new LinkedHashMap<>();
        for (Map.Entry<String, String> e : asignaciones.entrySet()) {
            if (registradas.contains(e.getKey())) limpias.put(e.getKey(), e.getValue());
        }
        return limpias;
    }
}
