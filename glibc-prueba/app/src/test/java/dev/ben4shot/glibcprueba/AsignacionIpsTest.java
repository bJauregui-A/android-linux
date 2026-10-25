package dev.ben4shot.glibcprueba;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertThrows;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.junit.Test;

public class AsignacionIpsTest {
    @Test
    public void primeraLibreSinAsignacionesEsLaPuntoDos() {
        assertEquals("10.0.0.2", AsignacionIps.primeraLibre("10.0.0.0/24", Collections.<String>emptyList()));
    }

    @Test
    public void primeraLibreRellenaHuecos() {
        assertEquals("10.0.0.3", AsignacionIps.primeraLibre("10.0.0.0/24", Arrays.asList("10.0.0.2", "10.0.0.4")));
    }

    @Test
    public void primeraLibreNuncaEsElGateway() {
        assertNotEquals("10.0.0.1", AsignacionIps.primeraLibre("10.0.0.0/24", Collections.<String>emptyList()));
        assertNotEquals("10.0.0.1", AsignacionIps.primeraLibre("10.0.0.0/24", Arrays.asList("10.0.0.2")));
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

    @Test
    public void primeraLibreEnUnSlash16PasaAlTercerOcteto() {
        List<String> ocupadas = new ArrayList<>();
        for (int i = 2; i <= 255; i++) ocupadas.add("10.0.0." + i);
        assertEquals("10.0.1.0", AsignacionIps.primeraLibre("10.0.0.0/16", ocupadas));
    }

    @Test
    public void primeraLibreEnOtroRango() {
        assertEquals("192.168.5.2", AsignacionIps.primeraLibre("192.168.5.0/24", Collections.<String>emptyList()));
    }

    @Test
    public void primeraLibreConSubredLlenaFallaSinUsarLaDifusion() {
        List<String> ocupadas = new ArrayList<>();
        for (int i = 2; i <= 254; i++) ocupadas.add("10.0.0." + i);
        assertThrows(IllegalStateException.class,
                () -> AsignacionIps.primeraLibre("10.0.0.0/24", ocupadas));
    }
}
