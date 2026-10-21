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
import java.io.FileWriter;
import java.net.InetAddress;
import java.util.ArrayList;
import java.util.List;

// Servicio en primer plano dueño de los procesos Linux (el escritorio y la sesión de bash):
// las activities se pueden cerrar (o girar) sin que Android mate los procesos glibc.
public class TerminalService extends Service implements TerminalSessionClient {
    private static final String TAG = "TERMINAL";
    private static final String CANAL = "terminal";
    // WaylandActivity lo manda al abrirse: arrancar la sesión gráfica si no está corriendo.
    static final String INICIAR_ESCRITORIO = "dev.ben4shot.glibcprueba.INICIAR_ESCRITORIO";

    private final IBinder binder = new Local();
    private TerminalSession sesion;
    private boolean instalando; // la sesión es el instalador (Instalador.java)
    private TerminalView vista; // la de la activity visible, o null
    private Process escritorio;
    private List<String> entornoEscritorio; // entorno común de la sesión Wayland

    class Local extends Binder {
        TerminalService servicio() { return TerminalService.this; }
    }

    @Override
    public IBinder onBind(Intent intent) { return binder; }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        NotificationManager nm = getSystemService(NotificationManager.class);
        nm.createNotificationChannel(new NotificationChannel(CANAL, "Terminal", NotificationManager.IMPORTANCE_LOW));
        PendingIntent abrir = PendingIntent.getActivity(this, 0,
                new Intent(this, WaylandActivity.class), PendingIntent.FLAG_IMMUTABLE);
        Notification n = new Notification.Builder(this, CANAL)
                .setSmallIcon(android.R.drawable.ic_menu_manage)
                .setContentTitle("Linux")
                .setContentText("procesos Linux corriendo")
                .setContentIntent(abrir)
                .setOngoing(true)
                .build();
        if (Build.VERSION.SDK_INT >= 34) startForeground(1, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE);
        else startForeground(1, n);
        if (intent != null && INICIAR_ESCRITORIO.equals(intent.getAction())) iniciarEscritorio();
        return START_NOT_STICKY;
    }

    @Override
    public void onDestroy() {
        if (sesion != null) sesion.finishIfRunning();
        if (escritorio != null) escritorio.destroy();
        super.onDestroy();
    }

    TerminalSession sesion() {
        if (sesion == null) sesion = crearSesion();
        return sesion;
    }

    void setVista(TerminalView v) {
        vista = v;
        if (sesion != null) sesion.updateTerminalSessionClient(this);
    }

    // La próxima vez que se abra la terminal arranca un bash nuevo.
    void cerrarSesion() {
        sesion = null;
        terminarSiNoQuedaNada();
    }

    // Sin escritorio ni bash no queda nada que cuidar.
    private void terminarSiNoQuedaNada() {
        boolean bash = sesion != null && sesion.isRunning();
        boolean vivo = escritorio != null && escritorio.isAlive();
        if (!bash && !vivo) terminar();
    }

    void terminar() {
        stopForeground(STOP_FOREGROUND_REMOVE);
        stopSelf();
    }

    // Shell de la instalación seleccionada a través de su cargador; el cwd es la ruta real
    // (el pty lo abre libtermux.so, que es bionic), el resto ya va dentro del prefijo.
    private TerminalSession crearSesion() {
        AdaptadorInstalacion instalacion = SistemaLinux.adaptadorSeleccionado(this);
        File prefijo = instalacion.raiz(this);
        if (!instalacion.instalada(this) && instalacion.instaladorDisponible(this)) {
            new File(prefijo, "etc").mkdirs();
            List<String> env = entorno(instalacion, prefijo);
            try {
                String[] args = instalacion.comandoInstalacion(this, env);
                instalando = true;
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
        Log.i(TAG, "sesión Linux: " + instalacion.id() + ", cargador " + cargador + ", prefijo " + prefijo);
        return new TerminalSession(cargador, new File(prefijo, instalacion.home(prefijo)).getAbsolutePath(), args,
                env.toArray(new String[0]), 5000, this);
    }

    // Sesión Wayland en segundo plano (bash -l para tomar /etc/profile).
    synchronized void iniciarEscritorio() {
        if (escritorio != null && escritorio.isAlive()) return;
        AdaptadorInstalacion instalacion = SistemaLinux.adaptadorSeleccionado(this);
        if (!instalacion.instalada(this) && instalacion.instaladorDisponible(this)) return; // primero el instalador
        File prefijo = instalacion.raiz(this);
        String cargador = instalacion.cargador(this);
        entornoEscritorio = entorno(instalacion, prefijo);
        // HyperOS ata algunos hilos de la app (el que lanza procesos) a los núcleos grandes
        // (6-7) y todo lo de sway lo heredaba: juego, Wine, Xwayland y Steam en 2 núcleos.
        // El cpuset top-app permite 0-7; abrir la afinidad no necesita root.
        String cmd = "taskset -p ff $$ > /dev/null 2>&1; exec "
                + instalacion.comandoRescate() + " > /tmp/rescate-grafico.log 2>&1";
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
        // El selector administra el compositor elegido y usa sway como rescate. El perfil
        // gráfico crea un bus D-Bus efímero que comparte con el compositor y sus servicios.
        String sesion = instalacion.supervisorSesion();
        boolean supervisor = !BuildConfig.DIAGNOSTICO && new File(prefijo, sesion).exists();
        ProcessBuilder pb;
        if (supervisor) {
            pb = new ProcessBuilder(cargador, "/usr/bin/bash", "-lc", "exec " + sesion);
        } else {
            pb = new ProcessBuilder(cargador, "/usr/bin/bash", "-lc", cmd);
        }
        entornoLinux(pb);
        if (supervisor) pb.environment().put("ARCH_ANDROID_SESSION_START", "1");
        try {
            Process p = pb.start();
            escritorio = p;
            Log.i(TAG, "sesión Wayland iniciada");
            Portapapeles.iniciar(this);
            Audio.iniciar(this);
            Mandos.iniciar(this);
            new Thread(() -> {
                try {
                    Log.i(TAG, "sesión Wayland terminó: " + p.waitFor());
                } catch (InterruptedException ignorada) {
                    return;
                }
                new android.os.Handler(getMainLooper()).post(this::terminarSiNoQuedaNada);
            }, "escritorio").start();
        } catch (java.io.IOException e) {
            Log.e(TAG, "sesión Wayland", e);
        }
    }

    boolean escritorioVivo() {
        Process p = escritorio;
        return p != null && p.isAlive();
    }

    // El supervisor publica el socket real del compositor anidado tras detectarlo.
    private String waylandDisplay() {
        File f = new File(SistemaLinux.adaptadorSeleccionado(this).raiz(this), Wayland.runtimeDir().substring(1) + "/arch-android-display");
        try (java.io.BufferedReader r = new java.io.BufferedReader(new java.io.FileReader(f))) {
            String s = r.readLine();
            if (s != null && s.matches("[A-Za-z0-9_.-]+")) return s;
        } catch (java.io.IOException ignored) { }
        return "wayland-1";
    }

    // Un programa Linux conectado al compositor elegido.
    ProcessBuilder linux(String... args) {
        AdaptadorInstalacion instalacion = SistemaLinux.adaptadorSeleccionado(this);
        String[] todo = new String[args.length + 1];
        todo[0] = instalacion.cargador(this);
        System.arraycopy(args, 0, todo, 1, args.length);
        ProcessBuilder pb = new ProcessBuilder(todo);
        entornoLinux(pb);
        pb.environment().put("WAYLAND_DISPLAY", waylandDisplay());
        return pb;
    }

    private void entornoLinux(ProcessBuilder pb) {
        AdaptadorInstalacion instalacion = SistemaLinux.adaptadorSeleccionado(this);
        pb.directory(new File(instalacion.raiz(this), instalacion.home(instalacion.raiz(this))));
        pb.environment().clear();
        for (String v : entornoEscritorio) {
            int i = v.indexOf('=');
            pb.environment().put(v.substring(0, i), v.substring(i + 1));
        }
        String bus = leerBusSesion(instalacion.raiz(this));
        if (bus != null) pb.environment().put("DBUS_SESSION_BUS_ADDRESS", bus);
    }

    private void agregarBusSesion(List<String> env, File prefijo) {
        String bus = leerBusSesion(prefijo);
        if (bus != null) env.add("DBUS_SESSION_BUS_ADDRESS=" + bus);
    }

    private String leerBusSesion(File prefijo) {
        File f = new File(prefijo, Wayland.runtimeDir().substring(1) + "/arch-android-bus");
        try (java.io.BufferedReader r = new java.io.BufferedReader(new java.io.FileReader(f))) {
            String bus = r.readLine();
            return bus == null || bus.isBlank() ? null : bus;
        } catch (java.io.IOException ignorada) {
            return null;
        }
    }

    // Entorno del host Android común a las instalaciones Linux.
    private List<String> entorno(AdaptadorInstalacion instalacion, File prefijo) {
        String homeLinux = instalacion.home(prefijo);
        File home = new File(prefijo, homeLinux);
        if (instalacion.instalada(this)) home.mkdirs(); // al instalar lo crea el adaptador
        instalacion.preparar(this, prefijo);
        escribirResolvConf(prefijo);
        Wayland.iniciar(this);
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
    public void onTextChanged(TerminalSession s) { if (vista != null) vista.onScreenUpdated(); }

    @Override
    public void onTitleChanged(TerminalSession s) { }

    @Override
    public void onSessionFinished(TerminalSession s) {
        if (instalando && s == sesion) {
            // Terminó el instalador: si quedó todo, al escritorio (la terminal vuelve a ser bash)
            instalando = false;
            sesion = null;
            if (SistemaLinux.adaptadorSeleccionado(this).instalada(this)) {
                if (vista != null && vista.getContext() instanceof android.app.Activity)
                    ((android.app.Activity) vista.getContext()).finish();
                startActivity(new Intent(this, WaylandActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
                return;
            }
        }
        if (vista != null) vista.onScreenUpdated();
        else terminarSiNoQuedaNada();
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
    public void onColorsChanged(TerminalSession s) { if (vista != null) vista.invalidate(); }

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
}
