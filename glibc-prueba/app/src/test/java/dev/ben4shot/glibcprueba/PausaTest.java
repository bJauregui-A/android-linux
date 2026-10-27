package dev.ben4shot.glibcprueba;

import static org.junit.Assert.assertEquals;

import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.Set;
import java.util.TreeSet;

import org.junit.Test;

public class PausaTest {
    private static final String RAIZ = "/data/user/0/app/files/instancias/sfce";

    private static Pausa.Proceso p(int pid, int ppid, String cmdline, String cwd) {
        return new Pausa.Proceso(pid, ppid, cmdline, cwd);
    }

    private static Set<Integer> pids(List<Pausa.Proceso> procs, int... excluir) {
        Set<Integer> ex = new TreeSet<>();
        for (int e : excluir) ex.add(e);
        return new TreeSet<>(Pausa.pidsAPausar(procs, RAIZ, ex));
    }

    @Test
    public void pausaLosProcesosDeLaInstanciaPorCmdlineOCwd() {
        List<Pausa.Proceso> procs = Arrays.asList(
                p(10, 1, "libldp.so --argv0 xfwm4 " + RAIZ + "/usr/bin/xfwm4", "/"),
                p(11, 1, "sleep 100", RAIZ + "/home/user"),
                p(12, 1, "dev.ben4shot.glibcprueba.sdk36:x11", "/"));
        assertEquals(new TreeSet<>(Arrays.asList(10, 11)), pids(procs));
    }

    @Test
    public void noTocaOtraInstanciaConPrefijoParecido() {
        List<Pausa.Proceso> procs = Collections.singletonList(
                p(20, 1, "libldp.so " + RAIZ + "-2/usr/bin/sway", RAIZ + "-2"));
        assertEquals(new TreeSet<>(), pids(procs));
    }

    @Test
    public void dejaVivaLaTerminalDeLaInstanciaYSusHijos() {
        List<Pausa.Proceso> procs = Arrays.asList(
                p(30, 1, "libldp.so " + RAIZ + "/usr/bin/bash", RAIZ),        // la terminal (excluida)
                p(31, 30, "libldp.so " + RAIZ + "/usr/bin/pacman", RAIZ),     // su hijo
                p(32, 31, "libldp.so " + RAIZ + "/usr/bin/curl", RAIZ),       // su nieto
                p(33, 1, "libldp.so " + RAIZ + "/usr/bin/xfce4-panel", RAIZ));
        assertEquals(new TreeSet<>(Collections.singletonList(33)), pids(procs, 30));
    }

    @Test
    public void sinProcesosNoPausaNada() {
        assertEquals(new TreeSet<>(), pids(Collections.emptyList()));
    }

    // Al cambiar la opción, se aplica ya a los escritorios que quedaron atrás; el que se ve no se toca.
    @Test
    public void alCambiarLaOpcionSeAplicaALosDeFondo() {
        assertEquals(Arrays.asList("xfce", "openbox"),
                Pausa.enFondo(Arrays.asList("sway", "xfce", "openbox"), "sway"));
        assertEquals(Arrays.asList("sway", "xfce"), Pausa.enFondo(Arrays.asList("sway", "xfce"), null));
    }
}
