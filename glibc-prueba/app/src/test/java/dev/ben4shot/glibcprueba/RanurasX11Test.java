package dev.ben4shot.glibcprueba;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;

import org.junit.Test;

public class RanurasX11Test {
    @Test
    public void cadaInstanciaTomaLaPrimeraRanuraLibre() {
        RanurasX11 r = new RanurasX11(3);
        assertEquals(0, r.asignar("a"));
        assertEquals(1, r.asignar("b"));
        assertEquals(2, r.asignar("c"));
    }

    @Test
    public void laMismaInstanciaConservaSuRanura() {
        RanurasX11 r = new RanurasX11(3);
        r.asignar("a");
        assertEquals(1, r.asignar("b"));
        assertEquals(1, r.asignar("b"));
        assertEquals(1, r.de("b"));
    }

    @Test
    public void sinRanuraLibreDevuelveMenosUno() {
        RanurasX11 r = new RanurasX11(2);
        r.asignar("a");
        r.asignar("b");
        assertEquals(-1, r.asignar("c"));
        assertEquals(-1, r.de("c"));
    }

    @Test
    public void unaRanuraLiberadaSeReutiliza() {
        RanurasX11 r = new RanurasX11(2);
        r.asignar("a");
        r.asignar("b");
        r.liberar("a");
        assertEquals(0, r.asignar("c"));
        assertEquals(1, r.de("b"));
    }

    @Test
    public void liberarUnaInstanciaQueNoEstaNoHaceNada() {
        RanurasX11 r = new RanurasX11(2);
        r.asignar("a");
        r.liberar("z");
        assertEquals(0, r.de("a"));
    }

    @Test
    public void laMasAntiguaEsLaPrimeraEnAsignarse() {
        RanurasX11 r = new RanurasX11(3);
        r.asignar("a");
        r.asignar("b");
        r.asignar("c");
        assertEquals("a", r.masAntiguaExcepto("c"));
    }

    @Test
    public void laMasAntiguaNuncaEsLaExcluida() {
        RanurasX11 r = new RanurasX11(3);
        r.asignar("a");
        r.asignar("b");
        assertEquals("b", r.masAntiguaExcepto("a"));
    }

    @Test
    public void sinOtrasInstanciasNoHayMasAntigua() {
        RanurasX11 r = new RanurasX11(3);
        r.asignar("a");
        assertNull(r.masAntiguaExcepto("a"));
    }

    @Test
    public void volverATomarUnaInstanciaNoLaRejuvenece() {
        RanurasX11 r = new RanurasX11(3);
        r.asignar("a");
        r.asignar("b");
        r.asignar("a");
        assertEquals("a", r.masAntiguaExcepto("b"));
    }
}
