package dev.ben4shot.glibcprueba;

import static org.junit.Assert.assertEquals;

import java.util.Collections;
import org.junit.Test;

public class AsignacionIpsTest {
    @Test
    public void primeraLibreSinAsignacionesEsLaPuntoDos() {
        assertEquals("10.0.0.2", AsignacionIps.primeraLibre(Collections.<String>emptyList()));
    }
}
