package dev.ben4shot.glibcprueba;

import android.content.Context;
import android.system.Os;
import android.system.OsConstants;
import android.util.Log;

import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

// Opción "Al salir de un escritorio → se pausa por completo": SIGSTOP a los procesos de la instancia al irse su vista y
// SIGCONT al volver. Son de la instancia los que llevan su raíz en cmdline o en cwd (como limpiarProcesosLinux); la
// terminal de la instancia (TerminalActivity) y sus hijos no se tocan, para no congelarla mientras se usa.
final class Pausa {
    private static final String TAG = "PAUSA";
    private static final Set<String> pausadas = new HashSet<>();
    // Pausar y reanudar en orden y fuera del hilo principal (leer /proc tarda): irse y volver rápido no se cruza.
    private static final java.util.concurrent.ExecutorService hilo =
            java.util.concurrent.Executors.newSingleThreadExecutor();

    static final class Proceso {
        final int pid, ppid;
        final String cmdline, cwd;

        Proceso(int pid, int ppid, String cmdline, String cwd) {
            this.pid = pid;
            this.ppid = ppid;
            this.cmdline = cmdline;
            this.cwd = cwd;
        }
    }

    private Pausa() { }

    // Los pids de la instancia de `raiz`, salvo los de `excluir` y sus descendientes.
    static List<Integer> pidsAPausar(List<Proceso> procs, String raiz, Set<Integer> excluir) {
        Map<Integer, Integer> padre = new HashMap<>();
        for (Proceso p : procs) padre.put(p.pid, p.ppid);
        List<Integer> r = new ArrayList<>();
        for (Proceso p : procs) {
            if (!deLaInstancia(p, raiz) || desciendeDe(p.pid, excluir, padre)) continue;
            r.add(p.pid);
        }
        return r;
    }

    private static boolean deLaInstancia(Proceso p, String raiz) {
        if (p.cwd != null && (p.cwd.equals(raiz) || p.cwd.startsWith(raiz + "/"))) return true;
        if (p.cmdline == null) return false;
        for (int i = p.cmdline.indexOf(raiz); i >= 0; i = p.cmdline.indexOf(raiz, i + 1)) {
            int fin = i + raiz.length();
            if (fin == p.cmdline.length() || p.cmdline.charAt(fin) == '/' || p.cmdline.charAt(fin) == ' ') return true;
        }
        return false;
    }

    private static boolean desciendeDe(int pid, Set<Integer> excluir, Map<Integer, Integer> padre) {
        for (int i = 0, p = pid; i < 64 && p > 1; i++) {
            if (excluir.contains(p)) return true;
            Integer pp = padre.get(p);
            if (pp == null) return false;
            p = pp;
        }
        return false;
    }

    static synchronized Set<String> pausadas() {
        return new HashSet<>(pausadas);
    }

    // Los escritorios que no se están viendo.
    static List<String> enFondo(Iterable<String> conEscritorio, String alFrente) {
        List<String> r = new ArrayList<>();
        for (String id : conEscritorio) if (!id.equals(alFrente)) r.add(id);
        return r;
    }

    // La opción "al salir" cambió: se aplica ya a los escritorios de fondo, sin esperar a que se vuelva a salir de ellos.
    static void aplicarOpcion(Context c, String alFrente) {
        boolean pausar = Opciones.pausaAlSalir(Opciones.alSalir(c));
        for (String id : enFondo(TerminalService.idsConEscritorio(), alFrente)) {
            if (pausar) alIrse(c, id);
            else alVolver(c, id);
        }
    }

    // La vista del escritorio se fue: si la opción lo pide, se pausa la instancia (salvo su terminal).
    static void alIrse(Context c, String id) {
        if (id == null || !Opciones.pausaAlSalir(Opciones.alSalir(c))) return;
        Context app = c.getApplicationContext();
        Set<Integer> terminal = TerminalService.pidsTerminal(id);
        hilo.execute(() -> pausar(app, id, terminal));
    }

    static void alVolver(Context c, String id) {
        if (id == null) return;
        Context app = c.getApplicationContext();
        hilo.execute(() -> reanudar(app, id));
    }

    static synchronized void pausar(Context c, String id, Set<Integer> excluir) {
        String raiz = SistemaLinux.raiz(c, id).getAbsolutePath();
        int n = 0;
        // dos pasadas: lo que nació mientras se paraba la primera
        for (int vuelta = 0; vuelta < 2; vuelta++) {
            for (int pid : pidsAPausar(leerProcesos(), raiz, excluir)) {
                if (senal(pid, OsConstants.SIGSTOP)) n++;
            }
        }
        pausadas.add(id);
        Log.i(TAG, "pausada " + id + " (" + n + " señales)");
    }

    // Idempotente: también se llama antes de cerrar la instancia (un proceso parado no atiende SIGTERM).
    static synchronized void reanudar(Context c, String id) {
        if (!pausadas.remove(id)) return;
        String raiz = SistemaLinux.raiz(c, id).getAbsolutePath();
        int n = 0;
        for (int pid : pidsAPausar(leerProcesos(), raiz, new HashSet<>())) {
            if (senal(pid, OsConstants.SIGCONT)) n++;
        }
        Log.i(TAG, "reanudada " + id + " (" + n + " procesos)");
    }

    // Cierre del escritorio: matar el proceso de arriba deja vivos los que ya colgaban de init (dbus-daemon, xfconfd,
    // tint2, at-spi...). Se termina todo lo de la instancia salvo su terminal: SIGTERM y, a los 2 s, SIGKILL.
    static void terminarSesion(Context c, String id, Set<Integer> excluir) {
        reanudar(c, id);   // un proceso parado no atiende SIGTERM
        String raiz = SistemaLinux.raiz(c, id).getAbsolutePath();
        List<Integer> pids = pidsAPausar(leerProcesos(), raiz, excluir);
        if (pids.isEmpty()) return;
        for (int pid : pids) senal(pid, OsConstants.SIGTERM);
        for (int i = 0; i < 20; i++) {
            pids = pidsAPausar(leerProcesos(), raiz, excluir);
            if (pids.isEmpty()) break;
            try { Thread.sleep(100); } catch (InterruptedException e) { break; }
        }
        for (int pid : pids) senal(pid, OsConstants.SIGKILL);
        Log.i(TAG, "sesión cerrada " + id + (pids.isEmpty() ? "" : " (" + pids.size() + " a la fuerza)"));
    }

    private static boolean senal(int pid, int s) {
        if (pid == android.os.Process.myPid()) return false;
        try {
            Os.kill(pid, s);
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    private static List<Proceso> leerProcesos() {
        List<Proceso> r = new ArrayList<>();
        String[] dirs = new File("/proc").list();
        if (dirs == null) return r;
        for (String d : dirs) {
            if (d.isEmpty() || !Character.isDigit(d.charAt(0))) continue;
            try {
                int pid = Integer.parseInt(d);
                String stat = new String(Files.readAllBytes(new File("/proc/" + d + "/stat").toPath()), StandardCharsets.UTF_8);
                // pid (comm) estado ppid ...: comm puede tener espacios y paréntesis, se corta en el último ")"
                String[] campos = stat.substring(stat.lastIndexOf(')') + 2).split(" ");
                int ppid = Integer.parseInt(campos[1]);
                String cmd = new String(Files.readAllBytes(new File("/proc/" + d + "/cmdline").toPath()),
                        StandardCharsets.UTF_8).replace('\0', ' ').trim();
                String cwd = null;
                try { cwd = Os.readlink("/proc/" + d + "/cwd"); } catch (Exception ignorada) { }
                r.add(new Proceso(pid, ppid, cmd, cwd));
            } catch (Exception ignorada) { }     // terminó mientras se leía, o es de otro usuario
        }
        return r;
    }
}
