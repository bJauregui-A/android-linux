package dev.ben4shot.glibcprueba;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotEquals;

import java.util.Arrays;
import java.util.Collections;
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
}
