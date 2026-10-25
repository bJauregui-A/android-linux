package dev.ben4shot.glibcprueba;

import static org.junit.Assert.assertEquals;

import java.util.Arrays;
import org.junit.Test;

public class CarpetasInstanciasTest {
    @Test
    public void sueltasDevuelveSoloLasCarpetasQueNoEstanRegistradas() {
        assertEquals(Arrays.asList("instancias/arch-arm64"),
                CarpetasInstancias.sueltas(
                        Arrays.asList("instancias/arch-principal", "instancias/arch-arm64", "instancias/t-1725"),
                        Arrays.asList("instancias/arch-principal", "instancias/t-1725")));
    }
}
