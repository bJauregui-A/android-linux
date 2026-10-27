package dev.ben4shot.glibcprueba;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

public class FinInstalacionTest {
    @Test
    public void conPantallaYVistaAbreElEscritorio() {
        assertEquals(FinInstalacion.Destino.ABRIR, FinInstalacion.destino(false, true));
    }

    @Test
    public void conPantallaSinVistaTambienAbreElEscritorio() {
        assertEquals(FinInstalacion.Destino.ABRIR, FinInstalacion.destino(false, false));
    }

    @Test
    public void sinPantallaYNadieMirandoNoAbreNada() {
        assertEquals(FinInstalacion.Destino.NADA, FinInstalacion.destino(true, false));
    }

    // El usuario abrió la instancia mientras se instalaba (instancia de prueba creada sin pantalla): está mirando
    // la terminal del instalador, así que se comporta como una instalación normal.
    @Test
    public void sinPantallaPeroConLaTerminalAVistaAbreElEscritorio() {
        assertEquals(FinInstalacion.Destino.ABRIR, FinInstalacion.destino(true, true));
    }
}
