package dev.ben4shot.glibcprueba;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

public class EscalaX11Test {
    @Test
    public void sinArchivoUsaLaEscalaDelTelefono() {
        assertEquals(240, EscalaX11.dpi(null));
    }

    @Test
    public void leeLaEscalaDelArchivo() {
        assertEquals(192, EscalaX11.dpi("ANDROID_ESCALA=2\n"));
    }

    @Test
    public void aceptaDecimales() {
        assertEquals(144, EscalaX11.dpi("ANDROID_ESCALA=1.5"));
    }

    @Test
    public void ignoraComentariosYOtrasVariables() {
        assertEquals(288, EscalaX11.dpi("# la escala\nWLR_RENDERER=pixman\n  ANDROID_ESCALA=3  \n"));
    }

    @Test
    public void siSeRepiteGanaLaUltima() {
        assertEquals(96, EscalaX11.dpi("ANDROID_ESCALA=2\nANDROID_ESCALA=1\n"));
    }

    @Test
    public void unValorQueNoEsNumeroUsaLaEscalaDelTelefono() {
        assertEquals(240, EscalaX11.dpi("ANDROID_ESCALA=mucha\n"));
    }

    @Test
    public void ceroONegativaUsaLaEscalaDelTelefono() {
        assertEquals(240, EscalaX11.dpi("ANDROID_ESCALA=0\n"));
        assertEquals(240, EscalaX11.dpi("ANDROID_ESCALA=-2\n"));
    }

    @Test
    public void archivoSinLaVariableUsaLaEscalaDelTelefono() {
        assertEquals(240, EscalaX11.dpi("FOO=bar\n"));
    }
}
