package dev.ben4shot.glibcprueba;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.net.ConnectivityManager;
import android.net.LinkProperties;
import android.os.Binder;
import android.os.Build;
import android.os.IBinder;
import android.util.Log;

import com.termux.terminal.TerminalSession;
import com.termux.terminal.TerminalSessionClient;
import com.termux.view.TerminalView;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileWriter;
import java.net.InetAddress;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Properties;
import java.util.concurrent.ConcurrentHashMap;

// Servicio en primer plano dueño de los procesos Linux (escritorios y sesiones de terminal):
// Soporta múltiples sesiones simultáneas e independientes en segundo plano.
public class TerminalService extends Service implements TerminalSessionClient {
    private static final String TAG = "TERMINAL";
    private static final String CANAL = "terminal";
    static final String INICIAR_ESCRITORIO = "dev.ben4shot.glibcprueba.INICIAR_ESCRITORIO";
    static final String REAJUSTAR_PANTALLA = "dev.ben4shot.glibcprueba.REAJUSTAR_PANTALLA";
    static final String CERRAR_SESION = "dev.ben4shot.glibcprueba.CERRAR_SESION";
    static final String CERRAR_INSTANCIA = "dev.ben4shot.glibcprueba.CERRAR_INSTANCIA";
    static final String EXTRA_INSTANCIA_ID = "instancia_id";

    public static class SesionInstancia {
        public final String id;
        public TerminalSession sesionTerminal;
        public Process procesoEscritorio;
        public List<String> entornoEscritorio;
        public boolean instalando;

        public SesionInstancia(String id) {
            this.id = id;
        }

        public boolean estaViva() {
            boolean term = sesionTerminal != null && sesionTerminal.isRunning();
            boolean esc = procesoEscritorio != null && procesoEscritorio.isAlive();
            return term || esc;
        }

        public boolean tieneTerminal() {
            return sesionTerminal != null && sesionTerminal.isRunning();
        }

        public boolean tieneEscritorio() {
            return procesoEscritorio != null && procesoEscritorio.isAlive();
        }
    }

    private static final Map<String, SesionInstancia> sesiones = new ConcurrentHashMap<>();
    private static String instanciaEnfocadaId;

    public static String instanciaActivaId() {
        if (instanciaEnfocadaId != null && estaCorriendo(instanciaEnfocadaId)) {
            return instanciaEnfocadaId;
        }
        for (SesionInstancia s : sesiones.values()) {
            if (s.estaViva()) return s.id;
        }
        return null;
    }

    public static boolean tieneSesionActiva() {
        for (SesionInstancia s : sesiones.values()) {
            if (s.estaViva()) return true;
        }
        return false;
    }

    public static boolean estaCorriendo(String id) {
        if (id == null) return false;
        SesionInstancia s = sesiones.get(id);
        return s != null && s.estaViva();
    }

    public static boolean tieneTerminal(String id) {
        if (id == null) return false;
        SesionInstancia s = sesiones.get(id);
        return s != null && s.tieneTerminal();
    }

    public static boolean tieneEscritorio(String id) {
        if (id == null) return false;
        SesionInstancia s = sesiones.get(id);
        return s != null && s.tieneEscritorio();
    }

    public static int contarSesionesActivas() {
        int c = 0;
        for (SesionInstancia s : sesiones.values()) {
            if (s.estaViva()) c++;
        }
        return c;
    }

    private final IBinder binder = new Local();
    private TerminalView vista;
    private TerminalSession sesionVisible;

    class Local extends Binder {
        TerminalService servicio() { return TerminalService.this; }
    }

    @Override
    public IBinder onBind(Intent intent) { return binder; }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent != null) {
            String accion = intent.getAction();
            String id = intent.getStringExtra(EXTRA_INSTANCIA_ID);
            if (CERRAR_SESION.equals(accion)) {
                if (id != null) {
                    cerrarInstancia(id);
                } else {
                    cerrarTodo();
                }
                return START_NOT_STICKY;
            }
            if (CERRAR_INSTANCIA.equals(accion)) {
                if (id == null) id = SistemaLinux.seleccionado(this);
                cerrarInstancia(id);
                return START_NOT_STICKY;
            }
            if (INICIAR_ESCRITORIO.equals(accion)) {
                if (id == null) id = SistemaLinux.seleccionado(this);
                iniciarEscritorioPara(id);
            }
            if (REAJUSTAR_PANTALLA.equals(accion)) {
                reajustarPantalla();
            }
        }
        actualizarNotificacion();
        RedManager.actualizar(this);
        RedManager.sincronizarIpsActivas(this, sesiones.keySet());
        return START_NOT_STICKY;
    }

    void actualizarNotificacion() {
        NotificationManager nm = getSystemService(NotificationManager.class);
        if (nm == null) return;
        nm.createNotificationChannel(new NotificationChannel(CANAL, "Terminal", NotificationManager.IMPORTANCE_LOW));

        List<SesionInstancia> vivas = new ArrayList<>();
        for (SesionInstancia s : sesiones.values()) {
            if (s.estaViva()) vivas.add(s);
        }
        if (vivas.isEmpty()) return;

        PendingIntent abrir = PendingIntent.getActivity(this, 0,
                new Intent(this, SistemaActivity.class), PendingIntent.FLAG_IMMUTABLE);

        String titulo;
        String texto;
        if (vivas.size() == 1) {
            SistemaLinux.Instancia inst = SistemaLinux.instancia(this, vivas.get(0).id);
            String nombre = inst != null ? inst.nombre : vivas.get(0).id;
            titulo = "✦ " + nombre;
            texto = "Sesión activa en segundo plano";
        } else {
            titulo = "✦ " + vivas.size() + " entornos en ejecución";
            StringBuilder sb = new StringBuilder();
            for (int i = 0; i < vivas.size(); i++) {
                if (i > 0) sb.append(", ");
                SistemaLinux.Instancia inst = SistemaLinux.instancia(this, vivas.get(i).id);
                sb.append(inst != null ? inst.nombre : vivas.get(i).id);
            }
            texto = sb.toString();
        }

        Notification.Builder nb = new Notification.Builder(this, CANAL)
                .setSmallIcon(android.R.drawable.ic_menu_manage)
                .setContentTitle(titulo)
                .setContentText(texto)
                .setContentIntent(abrir)
                .setOngoing(true);

        if (vivas.size() == 1) {
            String idInst = vivas.get(0).id;
            Intent it = new Intent(this, TerminalService.class)
                    .setAction(CERRAR_INSTANCIA)
                    .putExtra(EXTRA_INSTANCIA_ID, idInst);
            PendingIntent pi = PendingIntent.getService(this, 1, it, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
            nb.addAction(new Notification.Action.Builder(null, "✕ CERRAR", pi).build());
        } else if (vivas.size() == 2) {
            for (int i = 0; i < vivas.size(); i++) {
                String idInst = vivas.get(i).id;
                SistemaLinux.Instancia inst = SistemaLinux.instancia(this, idInst);
                String nom = inst != null ? inst.nombre : idInst;
                if (nom.length() > 10) nom = nom.substring(0, 10);
                Intent it = new Intent(this, TerminalService.class)
                        .setAction(CERRAR_INSTANCIA)
                        .putExtra(EXTRA_INSTANCIA_ID, idInst);
                PendingIntent pi = PendingIntent.getService(this, 10 + i, it, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
                nb.addAction(new Notification.Action.Builder(null, "✕ " + nom, pi).build());
            }
            PendingIntent piTodo = PendingIntent.getService(this, 99,
                    new Intent(this, TerminalService.class).setAction(CERRAR_SESION),
                    PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
            nb.addAction(new Notification.Action.Builder(null, "✕ TODO", piTodo).build());
        } else {
            String idEnf = instanciaEnfocadaId != null ? instanciaEnfocadaId : vivas.get(0).id;
            SistemaLinux.Instancia instEnf = SistemaLinux.instancia(this, idEnf);
            String nom = instEnf != null ? instEnf.nombre : idEnf;
            if (nom.length() > 10) nom = nom.substring(0, 10);
            Intent itEnf = new Intent(this, TerminalService.class)
                    .setAction(CERRAR_INSTANCIA)
                    .putExtra(EXTRA_INSTANCIA_ID, idEnf);
            PendingIntent piEnf = PendingIntent.getService(this, 50, itEnf, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
            nb.addAction(new Notification.Action.Builder(null, "✕ " + nom, piEnf).build());

            PendingIntent piTodo = PendingIntent.getService(this, 99,
                    new Intent(this, TerminalService.class).setAction(CERRAR_SESION),
                    PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
            nb.addAction(new Notification.Action.Builder(null, "✕ CERRAR TODO", piTodo).build());
        }

        Notification n = nb.build();
        if (Build.VERSION.SDK_INT >= 34) startForeground(1, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE);
        else startForeground(1, n);
    }

    public synchronized void cerrarInstancia(String id) {
        if (id == null) return;
        Log.i(TAG, "Cerrando instancia: " + id);
        RedManager.desregistrarIpActiva(this, id);
        SesionInstancia s = sesiones.remove(id);
        if (s != null) {
            s.instalando = false;
            cerrarSoloCompositor(s);
            if (s.sesionTerminal != null) {
                try {
                    s.sesionTerminal.finishIfRunning();
                } catch (Exception e) {
                    Log.w(TAG, "error al finalizar terminal de " + id, e);
                }
                s.sesionTerminal = null;
            }
        }
        AdaptadorInstalacion adp = SistemaLinux.adaptador(this, id);
        if (adp != null) {
            limpiarProcesosLinux(adp.raiz(this));
        }
        if (id.equals(instanciaEnfocadaId)) {
            instanciaEnfocadaId = null;
            for (SesionInstancia activa : sesiones.values()) {
                if (activa.estaViva()) {
                    instanciaEnfocadaId = activa.id;
                    break;
                }
            }
        }
        actualizarNotificacion();
        terminarSiNoQuedaNada();
    }

    public synchronized void cerrarSesionTerminal(String id) {
        if (id == null) return;
        SesionInstancia s = sesiones.get(id);
        if (s != null) {
            if (s.sesionTerminal != null) {
                try {
                    s.sesionTerminal.finishIfRunning();
                } catch (Exception ignorada) { }
                s.sesionTerminal = null;
            }
            if (!s.estaViva()) {
                sesiones.remove(id);
            }
        }
        actualizarNotificacion();
        terminarSiNoQuedaNada();
    }

    public synchronized void cerrarTodo() {
        Log.i(TAG, "Cerrando todas las instancias activas");
        List<String> ids = new ArrayList<>(sesiones.keySet());
        for (String id : ids) {
            cerrarInstancia(id);
        }
        sesiones.clear();
        instanciaEnfocadaId = null;
        terminar();
    }

    synchronized void cerrarSoloCompositor(SesionInstancia s) {
        if (s == null) return;
        try {
            Wayland.limpiarPantalla();
        } catch (Throwable ignorada) { }
        if (s.procesoEscritorio != null) {
            try {
                s.procesoEscritorio.destroyForcibly();
            } catch (Exception e) {
                try {
                    s.procesoEscritorio.destroy();
                } catch (Exception ignorada) { }
            }
            s.procesoEscritorio = null;
        }
        File raiz = SistemaLinux.raiz(this, s.id);
        if (raiz != null) {
            String path = raiz.getAbsolutePath();
            try {
                String[] cmd = new String[]{
                    "/system/bin/sh", "-c",
                    "rm -f " + path + "/tmp/arch-android-display " + path + "/run/user/*/wayland-[1-9]* " + path + "/run/user/*/sway-ipc.*.sock 2>/dev/null"
                };
                Runtime.getRuntime().exec(cmd).waitFor();
            } catch (Exception ignorada) { }
        }
    }

    synchronized void cerrarEscritorio() {
        String id = instanciaEnfocadaId != null ? instanciaEnfocadaId : SistemaLinux.seleccionado(this);
        if (id != null) {
            SesionInstancia s = sesiones.get(id);
            if (s != null) {
                cerrarSoloCompositor(s);
                if (!s.estaViva()) sesiones.remove(id);
            }
        }
        actualizarNotificacion();
        terminarSiNoQuedaNada();
    }

    private void limpiarProcesosLinux(File raiz) {
        if (raiz == null) return;
        try {
            int miPid = android.os.Process.myPid();
            String path = raiz.getAbsolutePath();
            String[] cmd = new String[]{
                "/system/bin/sh", "-c",
                "for p in /proc/[0-9]*; do " +
                "  pid=${p#/proc/}; " +
                "  if [ \"$pid\" != \"$$\" ] && [ \"$pid\" != \"" + miPid + "\" ]; then " +
                "    cmd=$(cat $p/cmdline 2>/dev/null | tr '\\0' ' '); " +
                "    cwd=$(readlink $p/cwd 2>/dev/null); " +
                "    case \"$cmd\" in *\"" + path + "\"*) kill -9 $pid 2>/dev/null; continue;; esac; " +
                "    case \"$cwd\" in \"" + path + "\"*) kill -9 $pid 2>/dev/null; continue;; esac; " +
                "  fi; " +
                "done; " +
                "rm -f " + path + "/tmp/arch-android-display " + path + "/run/user/*/wayland-[1-9]* " + path + "/run/user/*/sway-ipc.*.sock 2>/dev/null; " +
                "rm -rf " + path + "/dev/shm/.sysv " + path + "/dev/shm/* 2>/dev/null; " +
                "mkdir -p " + path + "/dev/shm/.sysv 2>/dev/null; " +
                "chmod 1777 " + path + "/dev/shm " + path + "/dev/shm/.sysv 2>/dev/null"
            };
            Runtime.getRuntime().exec(cmd).waitFor();
        } catch (Exception e) {
            Log.w(TAG, "limpieza procesos", e);
        }
    }

    @Override
    public void onDestroy() {
        RedManager.detenerTodo();
        cerrarTodo();
        super.onDestroy();
    }

    public synchronized TerminalSession sesionPara(String id) {
        if (id == null || id.isEmpty()) {
            id = SistemaLinux.seleccionado(this);
            if (id == null) id = "arch-principal";
        }
        instanciaEnfocadaId = id;
        SesionInstancia s = sesiones.get(id);
        if (s == null) {
            s = new SesionInstancia(id);
            sesiones.put(id, s);
        }
        if (s.sesionTerminal == null || !s.sesionTerminal.isRunning()) {
            s.sesionTerminal = crearSesion(id, s);
        }
        actualizarNotificacion();
        return s.sesionTerminal;
    }

    public TerminalSession sesion() {
        return sesionPara(SistemaLinux.seleccionado(this));
    }

    public void setVista(TerminalView v, TerminalSession s) {
        vista = v;
        sesionVisible = s;
        if (s != null) s.updateTerminalSessionClient(this);
    }

    public void setVista(TerminalView v) {
        setVista(v, sesionVisible);
    }

    void cerrarSesion() {
        String id = instanciaEnfocadaId != null ? instanciaEnfocadaId : SistemaLinux.seleccionado(this);
        cerrarSesionTerminal(id);
    }

    private void terminarSiNoQuedaNada() {
        boolean algunaViva = false;
        for (SesionInstancia s : sesiones.values()) {
            if (s.estaViva()) {
                algunaViva = true;
                break;
            }
        }
        if (!algunaViva) terminar();
    }

    void terminar() {
        stopForeground(STOP_FOREGROUND_REMOVE);
        stopSelf();
    }

    public boolean estaInstalando(String id) {
        if (id == null) return false;
        SesionInstancia s = sesiones.get(id);
        return s != null && s.instalando;
    }

    public boolean estaInstalando() {
        return estaInstalando(SistemaLinux.seleccionado(this));
    }

    // Shell de la instalación seleccionada a través de su cargador; el cwd es la ruta real
    // (el pty lo abre libtermux.so, que es bionic), el resto ya va dentro del prefijo.
    private TerminalSession crearSesion(String id, SesionInstancia sesionInst) {
        AdaptadorInstalacion instalacion = SistemaLinux.adaptador(this, id);
        File prefijo = instalacion.raiz(this);
        if (!instalacion.instalada(this) && instalacion.instaladorDisponible(this)) {
            new File(prefijo, "etc").mkdirs();
            List<String> env = entorno(instalacion, prefijo);
            try {
                String[] args = instalacion.comandoInstalacion(this, env);
                sesionInst.instalando = true;
                return new TerminalSession("/system/bin/sh", getFilesDir().getAbsolutePath(), args,
                        env.toArray(new String[0]), 5000, this);
            } catch (java.io.IOException e) {
                Log.e(TAG, "instalador", e);
            }
        }
        if (!new File(prefijo, "usr/bin/bash").exists()) {
            String msg = "falta la shell en " + prefijo + " (revisar la instalación Linux)";
            return new TerminalSession("/system/bin/sh", getFilesDir().getAbsolutePath(),
                    new String[]{"sh", "-c", "echo '" + msg + "'"}, new String[0], 2000, this);
        }
        String cargador = instalacion.cargador(this);
        List<String> env = entorno(instalacion, prefijo);
        agregarBusSesion(env, prefijo);
        String[] args = instalacion.comandoTerminal(this);
        Log.i(TAG, "sesión Linux [" + id + "]: " + instalacion.id() + ", cargador " + cargador + ", prefijo " + prefijo);
        return new TerminalSession(cargador, new File(prefijo, instalacion.home(prefijo)).getAbsolutePath(), args,
                env.toArray(new String[0]), 5000, this);
    }

    // Sesión Wayland en segundo plano (bash -l para tomar /etc/profile).
    synchronized void iniciarEscritorioPara(String idParam) {
        final String idActual = (idParam == null || idParam.isEmpty())
                ? (SistemaLinux.seleccionado(this) != null ? SistemaLinux.seleccionado(this) : "arch-principal")
                : idParam;
        instanciaEnfocadaId = idActual;

        SesionInstancia sesionInstTemp = sesiones.get(idActual);
        if (sesionInstTemp == null) {
            sesionInstTemp = new SesionInstancia(idActual);
            sesiones.put(idActual, sesionInstTemp);
        }
        final SesionInstancia sesionInst = sesionInstTemp;

        if (sesionInst.tieneEscritorio()) {
            actualizarNotificacion();
            return;
        }

        // Si otra instancia tiene un escritorio gráfico corriendo, cerrar solo su compositor
        // para dar paso al nuevo en la pantalla física, preservando su terminal y archivos intactos.
        for (SesionInstancia otra : sesiones.values()) {
            if (!otra.id.equals(idActual) && otra.tieneEscritorio()) {
                Log.i(TAG, "Cerrando compositor gráfico previo de " + otra.id + " para iniciar " + idActual);
                cerrarSoloCompositor(otra);
            }
        }

        actualizarNotificacion();
        AdaptadorInstalacion instalacion = SistemaLinux.adaptador(this, idActual);
        if (!instalacion.instalada(this) && instalacion.instaladorDisponible(this)) return;
        File prefijo = instalacion.raiz(this);
        if (!BuildConfig.DIAGNOSTICO && !CapaSesion.actualizar(this, instalacion, prefijo)) return;
        String cargador = instalacion.cargador(this);
        sesionInst.entornoEscritorio = entorno(instalacion, prefijo);
        String sesion = instalacion.supervisorSesion();
        boolean supervisor = !BuildConfig.DIAGNOSTICO && new File(prefijo, sesion).isFile();
        if (!BuildConfig.DIAGNOSTICO && !supervisor) {
            Log.e(TAG, "no inicio el escritorio: falta el supervisor común " + sesion);
            return;
        }
        String cmd = "taskset -p ff $$ > /dev/null 2>&1; exec sway > /tmp/rescate-grafico.log 2>&1";
        if (BuildConfig.DIAGNOSTICO) {
            try {
                File script = new File(prefijo, "tmp/probar-escritorios.sh");
                script.getParentFile().mkdirs();
                try (java.io.InputStream in = getAssets().open("probar-escritorios.sh");
                     java.io.FileOutputStream out = new java.io.FileOutputStream(script)) {
                    byte[] buffer = new byte[8192];
                    for (int n; (n = in.read(buffer)) != -1; ) out.write(buffer, 0, n);
                }
                script.setExecutable(true, false);
                cmd = "exec /usr/bin/bash /tmp/probar-escritorios.sh";
            } catch (java.io.IOException e) {
                Log.e(TAG, "script de diagnóstico", e);
            }
        }
        ProcessBuilder pb;
        if (supervisor) {
            pb = new ProcessBuilder(cargador, "/usr/bin/bash", "-lc", "exec " + sesion);
        } else {
            pb = new ProcessBuilder(cargador, "/usr/bin/bash", "-lc", cmd);
        }
        entornoLinuxPara(pb, idActual);
        if (supervisor) pb.environment().put("ARCH_ANDROID_SESSION_START", "1");
        try {
            Process p = pb.start();
            sesionInst.procesoEscritorio = p;
            Log.i(TAG, "sesión Wayland iniciada para [" + idActual + "]");
            Portapapeles.iniciar(this);
            Audio.iniciar(this);
            Mandos.iniciar(this);
            new Thread(() -> {
                try {
                    Log.i(TAG, "sesión Wayland [" + idActual + "] terminó: " + p.waitFor());
                } catch (InterruptedException ignorada) {
                    return;
                }
                new android.os.Handler(getMainLooper()).post(() -> {
                    if (sesionInst.procesoEscritorio == p) {
                        sesionInst.procesoEscritorio = null;
                        if (!sesionInst.estaViva()) {
                            sesiones.remove(idActual);
                        }
                    }
                    actualizarNotificacion();
                    terminarSiNoQuedaNada();
                });
            }, "escritorio-" + idActual).start();
        } catch (java.io.IOException e) {
            Log.e(TAG, "sesión Wayland [" + idActual + "]", e);
        }
    }

    synchronized void iniciarEscritorio() {
        iniciarEscritorioPara(SistemaLinux.seleccionado(this));
    }

    boolean escritorioVivo(String id) {
        if (id == null) return false;
        SesionInstancia s = sesiones.get(id);
        return s != null && s.tieneEscritorio();
    }

    boolean escritorioVivo() {
        return escritorioVivo(instanciaEnfocadaId != null ? instanciaEnfocadaId : SistemaLinux.seleccionado(this));
    }

    // El supervisor publica el socket real del compositor anidado tras detectarlo.
    private String waylandDisplayPara(File raiz) {
        File f = new File(raiz, Wayland.runtimeDir().substring(1) + "/linux-session-display");
        if (!f.isFile()) f = new File(raiz, Wayland.runtimeDir().substring(1) + "/arch-android-display");
        try (java.io.BufferedReader r = new java.io.BufferedReader(new java.io.FileReader(f))) {
            String s = r.readLine();
            if (s != null && s.matches("[A-Za-z0-9_.-]+")) return s;
        } catch (java.io.IOException ignored) { }
        return "wayland-1";
    }

    private String waylandDisplay() {
        File raiz = SistemaLinux.adaptadorSeleccionado(this).raiz(this);
        return waylandDisplayPara(raiz);
    }

    // Un programa Linux conectado al compositor elegido.
    ProcessBuilder linuxPara(String id, String... args) {
        AdaptadorInstalacion instalacion = SistemaLinux.adaptador(this, id);
        String[] todo = new String[args.length + 1];
        todo[0] = instalacion.cargador(this);
        System.arraycopy(args, 0, todo, 1, args.length);
        ProcessBuilder pb = new ProcessBuilder(todo);
        entornoLinuxPara(pb, id);
        aplicarEndpointPantallaPara(pb, id);
        return pb;
    }

    ProcessBuilder linux(String... args) {
        String id = instanciaEnfocadaId != null ? instanciaEnfocadaId : SistemaLinux.seleccionado(this);
        return linuxPara(id, args);
    }

    private File archivoSesionGrafica(File prefijo) {
        return new File(prefijo, Wayland.runtimeDir().substring(1)
                + "/linux-session.properties");
    }

    private Properties sesionGraficaPara(File prefijo) {
        Properties p = new Properties();
        File archivo = archivoSesionGrafica(prefijo);
        try (FileInputStream in = new FileInputStream(archivo)) {
            p.load(in);
            return p;
        } catch (java.io.IOException ignorada) {
            File anterior = new File(prefijo, Wayland.runtimeDir().substring(1)
                    + "/arch-android-session.properties");
            try (FileInputStream in = new FileInputStream(anterior)) {
                p.load(in);
                return p;
            } catch (java.io.IOException tambienIgnorada) {
                return null;
            }
        }
    }

    private Properties sesionGrafica() {
        AdaptadorInstalacion instalacion = SistemaLinux.adaptadorSeleccionado(this);
        return sesionGraficaPara(instalacion.raiz(this));
    }

    String protocoloPantallaPara(String id) {
        AdaptadorInstalacion instalacion = SistemaLinux.adaptador(this, id);
        File raiz = instalacion.raiz(this);
        Properties p = sesionGraficaPara(raiz);
        if (p != null) return p.getProperty("protocol");
        File runtime = new File(raiz, Wayland.runtimeDir().substring(1));
        return new File(runtime, "linux-session-display").isFile()
                || new File(runtime, "arch-android-display").isFile() ? "wayland" : null;
    }

    String protocoloPantalla() {
        String id = instanciaEnfocadaId != null ? instanciaEnfocadaId : SistemaLinux.seleccionado(this);
        return protocoloPantallaPara(id);
    }

    private void aplicarEndpointPantallaPara(ProcessBuilder pb, String id) {
        AdaptadorInstalacion instalacion = SistemaLinux.adaptador(this, id);
        File raiz = instalacion.raiz(this);
        Properties p = sesionGraficaPara(raiz);
        if (p == null) {
            pb.environment().put("WAYLAND_DISPLAY", waylandDisplayPara(raiz));
            return;
        }
        String protocolo = p.getProperty("protocol", "");
        String variable = p.getProperty("connection_variable", "");
        String endpoint = p.getProperty("endpoint", "");
        boolean wayland = "wayland".equals(protocolo) && "WAYLAND_DISPLAY".equals(variable);
        boolean x11 = "x11".equals(protocolo) && "DISPLAY".equals(variable);
        pb.environment().remove("WAYLAND_DISPLAY");
        pb.environment().remove("DISPLAY");
        if ((!wayland && !x11) || !endpoint.matches("[A-Za-z0-9_.:-]+")) return;
        pb.environment().put(variable, endpoint);
        pb.environment().put("XDG_SESSION_TYPE", protocolo);
    }

    private void aplicarEndpointPantalla(ProcessBuilder pb) {
        String id = instanciaEnfocadaId != null ? instanciaEnfocadaId : SistemaLinux.seleccionado(this);
        aplicarEndpointPantallaPara(pb, id);
    }

    private void entornoLinuxPara(ProcessBuilder pb, String id) {
        AdaptadorInstalacion instalacion = SistemaLinux.adaptador(this, id);
        File raiz = instalacion.raiz(this);
        pb.directory(new File(raiz, instalacion.home(raiz)));
        pb.environment().clear();
        SesionInstancia s = sesiones.get(id);
        List<String> env = (s != null && s.entornoEscritorio != null) ? s.entornoEscritorio : entorno(instalacion, raiz);
        for (String v : env) {
            int i = v.indexOf('=');
            if (i > 0) pb.environment().put(v.substring(0, i), v.substring(i + 1));
        }
        String bus = leerBusSesion(raiz);
        if (bus != null) pb.environment().put("DBUS_SESSION_BUS_ADDRESS", bus);
    }

    private void entornoLinux(ProcessBuilder pb) {
        String id = instanciaEnfocadaId != null ? instanciaEnfocadaId : SistemaLinux.seleccionado(this);
        entornoLinuxPara(pb, id);
    }

    private void agregarBusSesion(List<String> env, File prefijo) {
        String bus = leerBusSesion(prefijo);
        if (bus != null) env.add("DBUS_SESSION_BUS_ADDRESS=" + bus);
    }

    private String leerBusSesion(File prefijo) {
        File f = new File(prefijo, Wayland.runtimeDir().substring(1) + "/linux-session-bus");
        try (java.io.BufferedReader r = new java.io.BufferedReader(new java.io.FileReader(f))) {
            String bus = r.readLine();
            return bus == null || bus.isBlank() ? null : bus;
        } catch (java.io.IOException ignorada) {
            f = new File(prefijo, Wayland.runtimeDir().substring(1) + "/arch-android-bus");
            try (java.io.BufferedReader r = new java.io.BufferedReader(new java.io.FileReader(f))) {
                String bus = r.readLine();
                return bus == null || bus.isBlank() ? null : bus;
            } catch (java.io.IOException tambienIgnorada) {
                return null;
            }
        }
    }

    // Entorno del host Android común a las instalaciones Linux.
    private List<String> entorno(AdaptadorInstalacion instalacion, File prefijo) {
        String homeLinux = instalacion.home(prefijo);
        File home = new File(prefijo, homeLinux);
        if (instalacion.instalada(this)) home.mkdirs(); // al instalar lo crea el adaptador
        instalacion.preparar(this, prefijo);
        escribirResolvConf(prefijo);
        try {
            String vip = RedManager.ipParaInstancia(this, instalacion.id());
            RedManager.escribirVirtualIp(this, instalacion.id(), vip);
            RedManager.registrarIpActiva(this, instalacion.id());
        } catch (Exception ignorada) { }
        Wayland.iniciarPara(this, instalacion.id());
        Abrir.iniciar(this);
        Notificar.iniciar(this);
        PuertoAdb.iniciar(this);
        List<String> env = new ArrayList<>(List.of(
                "ANDROID_MODELO=" + Build.MODEL,
                "TERM=xterm-256color",
                "COLORTERM=truecolor",
                "TZ=" + java.util.TimeZone.getDefault().getID(),
                "XDG_RUNTIME_DIR=" + Wayland.runtimeDir(),
                "WAYLAND_DISPLAY=wayland-0",
                "WLR_NO_HARDWARE_CURSORS=1"));
        instalacion.agregarEntorno(this, prefijo, env);
        return env;
    }

    // DNS de la red activa de Android; 1.1.1.1 de respaldo (glibc usa hasta 3).
    static List<String> servidoresDns(android.content.Context c) {
        List<String> servidores = new ArrayList<>();
        try {
            ConnectivityManager cm = c.getSystemService(ConnectivityManager.class);
            LinkProperties lp = cm.getLinkProperties(cm.getActiveNetwork());
            if (lp != null) {
                for (InetAddress a : lp.getDnsServers()) {
                    if (servidores.size() < 2) servidores.add(a.getHostAddress());
                }
            }
        } catch (Exception e) {
            Log.e(TAG, "DNS de Android", e);
        }
        servidores.add("1.1.1.1");
        return servidores;
    }

    private void escribirResolvConf(File prefijo) {
        List<String> servidores = servidoresDns(this);
        StringBuilder sb = new StringBuilder("# escrito por la app al abrir la terminal\n");
        for (String s : servidores) sb.append("nameserver ").append(s).append('\n');
        File f = new File(prefijo, "etc/resolv.conf");
        f.delete(); // por si es un enlace
        try (FileWriter w = new FileWriter(f)) {
            w.write(sb.toString());
        } catch (Exception e) {
            Log.e(TAG, "resolv.conf", e);
        }
    }

    // --- TerminalSessionClient ---

    @Override
    public void onTextChanged(TerminalSession s) {
        if (vista != null && s == sesionVisible) {
            vista.post(vista::onScreenUpdated);
        }
    }

    @Override
    public void onTitleChanged(TerminalSession s) { }

    @Override
    public void onSessionFinished(TerminalSession s) {
        SesionInstancia dueña = null;
        for (SesionInstancia si : sesiones.values()) {
            if (si.sesionTerminal == s) {
                dueña = si;
                break;
            }
        }
        if (dueña != null) {
            if (dueña.instalando) {
                dueña.instalando = false;
                dueña.sesionTerminal = null;
                AdaptadorInstalacion adp = SistemaLinux.adaptador(this, dueña.id);
                if (adp != null && adp.instalada(this)) {
                    if (vista != null && s == sesionVisible && vista.getContext() instanceof android.app.Activity) {
                        ((android.app.Activity) vista.getContext()).finish();
                    }
                    File fEsc = new File(SistemaLinux.raiz(this, dueña.id), "var/lib/arch-android/escritorio");
                    boolean esSinEntorno = false;
                    try {
                        if (fEsc.exists()) {
                            String e = java.nio.file.Files.readString(fEsc.toPath()).trim();
                            if ("sin-entorno".equals(e)) esSinEntorno = true;
                        }
                    } catch (Exception ignorada) { }
                    if (esSinEntorno) {
                        Intent i = new Intent(this, TerminalActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                        i.putExtra(EXTRA_INSTANCIA_ID, dueña.id);
                        startActivity(i);
                    } else {
                        Intent i = new Intent(this, WaylandActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                        i.putExtra(EXTRA_INSTANCIA_ID, dueña.id);
                        startActivity(i);
                    }
                    return;
                }
            } else {
                dueña.sesionTerminal = null;
                if (!dueña.estaViva()) {
                    RedManager.desregistrarIpActiva(this, dueña.id);
                    sesiones.remove(dueña.id);
                }
            }
        }
        if (vista != null && s == sesionVisible) vista.onScreenUpdated();
        terminarSiNoQuedaNada();
        actualizarNotificacion();
    }

    @Override
    public void onCopyTextToClipboard(TerminalSession s, String texto) {
        getSystemService(ClipboardManager.class).setPrimaryClip(ClipData.newPlainText("terminal", texto));
    }

    @Override
    public void onPasteTextFromClipboard(TerminalSession s) {
        ClipData clip = getSystemService(ClipboardManager.class).getPrimaryClip();
        if (clip == null || clip.getItemCount() == 0) return;
        CharSequence texto = clip.getItemAt(0).coerceToText(this);
        if (texto != null && s.getEmulator() != null) s.getEmulator().paste(texto.toString());
    }

    @Override
    public void onBell(TerminalSession s) { }

    @Override
    public void onColorsChanged(TerminalSession s) {
        if (vista != null && s == sesionVisible) vista.invalidate();
    }

    @Override
    public void onTerminalCursorStateChange(boolean visible) { }

    @Override
    public Integer getTerminalCursorStyle() { return 0; } // bloque

    @Override
    public void logError(String tag, String msg) { Log.e(TAG, tag + ": " + msg); }

    @Override
    public void logWarn(String tag, String msg) { Log.w(TAG, tag + ": " + msg); }

    @Override
    public void logInfo(String tag, String msg) { Log.i(TAG, tag + ": " + msg); }

    @Override
    public void logDebug(String tag, String msg) { }

    @Override
    public void logVerbose(String tag, String msg) { }

    @Override
    public void logStackTraceWithMessage(String tag, String msg, Exception e) { Log.e(TAG, tag + ": " + msg, e); }

    @Override
    public void logStackTrace(String tag, Exception e) { Log.e(TAG, tag, e); }

    private void reajustarPantalla() {
        String id = instanciaEnfocadaId != null ? instanciaEnfocadaId : SistemaLinux.seleccionado(this);
        if (!escritorioVivo(id)) return;
        new Thread(() -> {
            try {
                linuxPara(id, "/usr/bin/bash", "-c",
                        "if command -v hyprctl >/dev/null 2>&1; then " +
                        "  hyprctl keyword monitor WAYLAND-1,preferred,auto,${ANDROID_ESCALA:-2.5} >/dev/null 2>&1; " +
                        "elif command -v swaymsg >/dev/null 2>&1; then " +
                        "  swaymsg reload >/dev/null 2>&1; " +
                        "fi; " +
                        "if [ -x /usr/local/bin/reajustar-pantalla ]; then /usr/local/bin/reajustar-pantalla; fi"
                ).start();
            } catch (Exception e) {
                Log.w(TAG, "Error al reajustar pantalla: " + e.getMessage());
            }
        }, "reajustar-pantalla").start();
    }
}
