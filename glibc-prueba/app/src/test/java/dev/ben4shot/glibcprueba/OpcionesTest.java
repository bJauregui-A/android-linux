package dev.ben4shot.glibcprueba;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public class OpcionesTest {
    @Test
    public void suenaLaInstanciaAlFrente() {
        assertEquals("sway", Opciones.instanciaQueSuena(Opciones.AUDIO_SILENCIO, "sway", "xfce"));
        assertEquals("sway", Opciones.instanciaQueSuena(Opciones.AUDIO_ULTIMA_VISTA, "sway", "xfce"));
    }

    @Test
    public void sinVistaAlFrenteYSilencioNoSuenaNada() {
        assertNull(Opciones.instanciaQueSuena(Opciones.AUDIO_SILENCIO, null, "xfce"));
    }

    @Test
    public void sinVistaAlFrenteSigueLaUltimaVista() {
        assertEquals("xfce", Opciones.instanciaQueSuena(Opciones.AUDIO_ULTIMA_VISTA, null, "xfce"));
    }

    @Test
    public void sinNingunaVistaNoSuenaNada() {
        assertNull(Opciones.instanciaQueSuena(Opciones.AUDIO_ULTIMA_VISTA, null, null));
        assertNull(Opciones.instanciaQueSuena(Opciones.AUDIO_SILENCIO, null, null));
    }

    @Test
    public void alSalirSoloPausaSiSeEligio() {
        assertTrue(Opciones.pausaAlSalir(Opciones.SALIR_PAUSAR));
        assertFalse(Opciones.pausaAlSalir(Opciones.SALIR_SIN_DIBUJAR));
        assertFalse(Opciones.pausaAlSalir(null));
        assertFalse(Opciones.pausaAlSalir("otro"));
    }

    @Test
    public void unaInstanciaPausadaNoSuena() {
        java.util.Set<String> pausadas = java.util.Collections.singleton("sway");
        assertNull(Opciones.instanciaQueSuena(Opciones.AUDIO_ULTIMA_VISTA, null, "sway", pausadas));
        assertEquals("xfce", Opciones.instanciaQueSuena(Opciones.AUDIO_ULTIMA_VISTA, null, "xfce", pausadas));
    }

    @Test
    public void unValorDesconocidoSeTrataComoSilencio() {
        assertNull(Opciones.instanciaQueSuena("otro", null, "xfce"));
    }
}
