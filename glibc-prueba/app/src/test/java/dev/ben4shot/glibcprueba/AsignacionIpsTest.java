package dev.ben4shot.glibcprueba;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotEquals;

import java.util.Arrays;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;
import org.junit.Test;

public class AsignacionIpsTest {
    @Test
    public void primeraLibreSinAsignacionesEsLaPuntoDos() {
        assertEquals("10.0.0.2", AsignacionIps.primeraLibre(Collections.<String>emptyList()));
    }

    @Test
    public void primeraLibreRellenaHuecos() {
        assertEquals("10.0.0.3", AsignacionIps.primeraLibre(Arrays.asList("10.0.0.2", "10.0.0.4")));
    }

    @Test
    public void primeraLibreNuncaEsElGateway() {
        assertNotEquals("10.0.0.1", AsignacionIps.primeraLibre(Collections.<String>emptyList()));
        assertNotEquals("10.0.0.1", AsignacionIps.primeraLibre(Arrays.asList("10.0.0.2")));
    }

    @Test
    public void limpiarQuitaLasAsignacionesDeInstanciasInexistentes() {
        Map<String, String> asignaciones = new LinkedHashMap<>();
        asignaciones.put("t-1725", "10.0.0.3");
        asignaciones.put("debian-63996", "10.0.0.4");
        asignaciones.put("debian_console-17094", "10.0.0.5");

        Map<String, String> limpias = AsignacionIps.limpiar(asignaciones,
                Arrays.asList("t-1725", "debian_console-17094"));

        Map<String, String> esperadas = new LinkedHashMap<>();
        esperadas.put("t-1725", "10.0.0.3");
        esperadas.put("debian_console-17094", "10.0.0.5");
        assertEquals(esperadas, limpias);
    }
}
