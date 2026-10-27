package dev.ben4shot.glibcprueba;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

public class CapaTest {
    @Test
    public void conElMismoHashNoEstaAtrasada() {
        assertFalse(Capa.atrasada("abc", "abc"));
    }

    @Test
    public void conHashesDistintosEstaAtrasada() {
        assertTrue(Capa.atrasada("abc", "def"));
    }

    // Instancia creada antes de B23: no tiene capa.sha256.
    @Test
    public void sinHashEnLaInstanciaEstaAtrasada() {
        assertTrue(Capa.atrasada("abc", ""));
    }

    // APK sin instalador (solo el cargador): no hay capa que llevar a la instancia.
    @Test
    public void sinHashEnElApkNoEstaAtrasada() {
        assertFalse(Capa.atrasada("", ""));
        assertFalse(Capa.atrasada("", "abc"));
    }

    // Atrasada: instalar.sh (MODO=actualizar) primero, y él hace exec del comando de siempre.
    @Test
    public void atrasadaAnteponeElInstalador() {
        String[] siempre = {"/ruta/libldp.so", "/usr/bin/bash", "-l"};
        assertArrayEquals(new String[]{"/system/bin/sh", "-c", "#script", "instalar.sh",
                        "/ruta/libldp.so", "/usr/bin/bash", "-l"},
                Capa.comando(true, "#script", siempre));
    }

    @Test
    public void alDiaEsElComandoDeSiempre() {
        String[] siempre = {"/ruta/libldp.so", "/usr/bin/bash", "-l"};
        assertArrayEquals(siempre, Capa.comando(false, "#script", siempre));
    }

    // /system/bin/sh es bionic: con el LD_PRELOAD de la instancia (una biblioteca de glibc) no arranca. instalar.sh lo
    // devuelve antes del exec.
    @Test
    public void apartaElLdPreloadDeLaInstancia() {
        List<String> env = new ArrayList<>(Arrays.asList("A=1", "LD_PRELOAD=/usr/local/turnip/lib/libegl-zink.so"));
        Capa.apartarPreload(env);
        assertEquals(Arrays.asList("A=1", "LINUX_LD_PRELOAD=/usr/local/turnip/lib/libegl-zink.so"), env);
    }
}
