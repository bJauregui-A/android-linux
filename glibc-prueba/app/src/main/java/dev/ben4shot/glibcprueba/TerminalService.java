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

// Servicio en primer plano dueño de los procesos Linux (sway y la sesión de bash):
// las activities se pueden cerrar (o girar) sin que Android mate los procesos glibc.
public class TerminalService extends Service implements TerminalSessionClient {
    private static final String TAG = "TERMINAL";
    private static final String CANAL = "terminal";
    static final String PREFIJO = "archlinux";
    // WaylandActivity lo manda al abrirse: arrancar sway si no está corriendo
    static final String SWAY = "dev.ben4shot.glibcprueba.SWAY";

    private final IBinder binder = new Local();
    private TerminalSession sesion;
    private TerminalView vista; // la de la activity visible, o null
    private Process sway;
    private List<String> entornoSway; // el de sway, para los programas que se le conectan

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
                .setContentTitle("Arch Linux")
                .setContentText("procesos Linux corriendo")
                .setContentIntent(abrir)
                .setOngoing(true)
                .build();
        if (Build.VERSION.SDK_INT >= 34) startForeground(1, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE);
        else startForeground(1, n);
        if (intent != null && SWAY.equals(intent.getAction())) iniciarSway();
        return START_NOT_STICKY;
    }

    @Override
    public void onDestroy() {
        if (sesion != null) sesion.finishIfRunning();
        if (sway != null) sway.destroy();
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

    // Sin sway ni bash no queda nada que cuidar.
    private void terminarSiNoQuedaNada() {
        boolean bash = sesion != null && sesion.isRunning();
        boolean escritorio = sway != null && sway.isAlive();
        if (!bash && !escritorio) terminar();
    }

    void terminar() {
        stopForeground(STOP_FOREGROUND_REMOVE);
        stopSelf();
    }

    // bash -l de Arch a través del cargador de la glibc propia; el cwd es la ruta real
    // (el pty lo abre libtermux.so, que es bionic), el resto ya va dentro del prefijo.
    private TerminalSession crearSesion() {
        File prefijo = new File(getFilesDir(), PREFIJO);
        if (!new File(prefijo, "usr/bin/bash").exists()) {
            String msg = "falta " + prefijo + " (instalar con scripts/instalar-arch.sh)";
            return new TerminalSession("/system/bin/sh", getFilesDir().getAbsolutePath(),
                    new String[]{"sh", "-c", "echo '" + msg + "'"}, new String[0], 2000, this);
        }
        String cargador = cargador();
        List<String> env = entorno(prefijo, cargador);
        String[] args = {"libldp.so", "/usr/bin/bash", "-l"};
        Log.i(TAG, "sesión: " + cargador + " /usr/bin/bash -l, prefijo " + prefijo);
        return new TerminalSession(cargador, new File(prefijo, "home/user").getAbsolutePath(), args,
                env.toArray(new String[0]), 5000, this);
    }

    // sway en segundo plano (bash -l para tomar /etc/profile), log en /tmp/sway.log.
    synchronized void iniciarSway() {
        if (sway != null && sway.isAlive()) return;
        File prefijo = new File(getFilesDir(), PREFIJO);
        if (!new File(prefijo, "usr/bin/sway").exists()) {
            Log.e(TAG, "falta sway en " + prefijo);
            return;
        }
        entornoSway = entorno(prefijo, cargador());
        // sway parchado (sway/compilar-sway.sh: achica las ventanas que no caben), si está
        String bin = new File(prefijo, "home/user/sway/bin/sway").exists()
                ? "/home/user/sway/bin/sway" : "sway";
        // HyperOS ata algunos hilos de la app (el que lanza procesos) a los núcleos grandes
        // (6-7) y todo lo de sway lo heredaba: juego, Wine, Xwayland y Steam en 2 núcleos.
        // El cpuset top-app permite 0-7; abrir la afinidad no necesita root.
        ProcessBuilder pb = new ProcessBuilder(cargador(), "/usr/bin/bash", "-lc",
                "taskset -p ff $$ > /dev/null 2>&1; exec " + bin + " > /tmp/sway.log 2>&1");
        entornoLinux(pb);
        try {
            Process p = pb.start();
            sway = p;
            Log.i(TAG, "sway iniciado");
            Portapapeles.iniciar(this);
            Audio.iniciar(this);
            Mandos.iniciar(this);
            new Thread(() -> {
                try {
                    Log.i(TAG, "sway terminó: " + p.waitFor());
                } catch (InterruptedException ignorada) {
                    return;
                }
                new android.os.Handler(getMainLooper()).post(this::terminarSiNoQuedaNada);
            }, "sway").start();
        } catch (java.io.IOException e) {
            Log.e(TAG, "sway", e);
        }
    }

    boolean swayVivo() {
        Process p = sway;
        return p != null && p.isAlive();
    }

    // Un programa Linux conectado a sway (wayland-1: el socket que abre sway anidado).
    ProcessBuilder linux(String... args) {
        String[] todo = new String[args.length + 1];
        todo[0] = cargador();
        System.arraycopy(args, 0, todo, 1, args.length);
        ProcessBuilder pb = new ProcessBuilder(todo);
        entornoLinux(pb);
        pb.environment().put("WAYLAND_DISPLAY", "wayland-1");
        return pb;
    }

    private void entornoLinux(ProcessBuilder pb) {
        pb.directory(new File(getFilesDir(), PREFIJO + "/home/user"));
        pb.environment().clear();
        for (String v : entornoSway) {
            int i = v.indexOf('=');
            pb.environment().put(v.substring(0, i), v.substring(i + 1));
        }
    }

    private String cargador() {
        return getApplicationInfo().nativeLibraryDir + "/libldp.so";
    }

    // Entorno de los procesos Linux; de paso deja listo el prefijo (DNS, sudo, Wayland).
    private List<String> entorno(File prefijo, String cargador) {
        File home = new File(prefijo, "home/user");
        home.mkdirs();
        // shm_open de glibc usa /dev/shm (traducido al prefijo): wlroots, foot...
        new File(prefijo, "dev/shm").mkdirs();
        escribirResolvConf(prefijo);
        escribirSudo(prefijo);
        Wayland.iniciar(this);
        Abrir.iniciar(this);
        Notificar.iniciar(this);
        List<String> env = new ArrayList<>(List.of(
                "GLIBC_PREFIX=" + prefijo,
                "GLIBC_LOADER=" + cargador,
                "HOME=/home/user",
                "USER=user",
                // kitty y foot abren $SHELL: zsh como en el PC (sway/zsh/), si está instalada
                "SHELL=" + (new File(prefijo, "usr/bin/zsh").exists() ? "/usr/bin/zsh" : "/usr/bin/bash"),
                "PATH=/usr/local/bin:/usr/bin",
                "TERM=xterm-256color",
                "COLORTERM=truecolor",
                "LANG=C.UTF-8",
                "TMPDIR=/tmp",
                "TZ=" + java.util.TimeZone.getDefault().getID(),
                "XDG_RUNTIME_DIR=" + Wayland.runtimeDir(),
                "WAYLAND_DISPLAY=wayland-0",
                "WLR_NO_HARDWARE_CURSORS=1", // el anfitrión no dibuja cursor: lo pinta sway
                // Vulkan: Turnip (KGSL) compilado en el teléfono (turnip/compilar-mesa.sh)
                "VK_ICD_FILENAMES=/home/user/turnip/share/vulkan/icd.d/freedreno_icd.aarch64.json",
                // OpenGL: Zink (mesa de Arch) sobre Turnip
                "MESA_LOADER_DRIVER_OVERRIDE=zink",
                // gdk-pixbuf carga imágenes con glycin, que las aísla con bwrap (namespaces: no
                // sin root). bwrap falla leyendo /proc/sys/kernel/overflowuid, glycin no reconoce
                // ese error y las apps GTK se caen con el primer ícono. La app ya es un sandbox.
                "GLYCIN_DISABLE_SANDBOX=i-know-the-risks",
                // Firefox: SELinux no deja reabrir un memfd por /proc/self/fd, el proceso
                // principal cae a /dev/shm sin sellos y los de contenido exigían F_SEAL_SHRINK
                // ("Shared memory PlatformHandle is not safe to map", señal 11).
                "MOZ_SHM_NO_SEALS=1",
                // Mandos: SDL (y Wine por SDL) los busca en /dev/input (Mandos.java); por udev
                // no los vería (Android no deja leer /sys/class/input ni los uevents).
                "SDL_JOYSTICK_DISABLE_UDEV=1"));
        // Escritorio por GPU: wlroots parchado (wlroots/compilar-wlroots.sh) con renderer
        // Vulkan, buffers android-ahb-v1 hacia el anfitrión y linux-dmabuf para los clientes.
        // Sin él, sway por CPU (pixman) y los clientes Vulkan por wl_shm.
        if (new File(home, "wlroots/lib/libwlroots-0.20.so").exists()) {
            env.add("WLR_RENDERER=vulkan");
            env.add("LD_LIBRARY_PATH=/home/user/wlroots/lib");
        } else {
            env.add("WLR_RENDERER=pixman");
            env.add("MESA_VK_WSI_DEBUG=sw");
        }
        // EGL en Wayland sin dmabuf: Zink + kopper por wl_shm (turnip/egl-zink.c)
        if (new File(home, "turnip/lib/libegl-zink.so").exists())
            env.add("LD_PRELOAD=/home/user/turnip/lib/libegl-zink.so");
        entornoPropio(new File(home, ".config/entorno-android"), env);
        return env;
    }

    // Variables propias de cada dispositivo (VAR=valor por línea, # comenta): reemplazan a
    // las de arriba. Ej. la tablet (Adreno 610): Turnip anuncia Vulkan 1.0 y wlroots pide 1.1.
    private static void entornoPropio(File f, List<String> env) {
        if (!f.exists()) return;
        try (java.io.BufferedReader r = new java.io.BufferedReader(new java.io.FileReader(f))) {
            for (String l; (l = r.readLine()) != null; ) {
                l = l.trim();
                int i = l.indexOf('=');
                if (l.startsWith("#") || i <= 0) continue;
                String clave = l.substring(0, i + 1);
                env.removeIf(v -> v.startsWith(clave));
                env.add(l);
            }
        } catch (java.io.IOException e) {
            Log.e(TAG, "entorno-android", e);
        }
    }

    // DNS de la red activa de Android; 1.1.1.1 de respaldo (glibc usa hasta 3).
    private void escribirResolvConf(File prefijo) {
        List<String> servidores = new ArrayList<>();
        try {
            ConnectivityManager cm = getSystemService(ConnectivityManager.class);
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

    // "sudo" = modo fakeroot de la glibc (pacman exige uid 0).
    private void escribirSudo(File prefijo) {
        File f = new File(prefijo, "usr/local/bin/sudo");
        if (f.exists()) return;
        f.getParentFile().mkdirs();
        try (FileWriter w = new FileWriter(f)) {
            w.write("#!/usr/bin/bash\n# fakeroot de la glibc propia, escrito por la app\nGLIBC_FAKEROOT=1 exec \"$@\"\n");
        } catch (Exception e) {
            Log.e(TAG, "sudo", e);
        }
        f.setExecutable(true, false);
    }

    // --- TerminalSessionClient ---

    @Override
    public void onTextChanged(TerminalSession s) { if (vista != null) vista.onScreenUpdated(); }

    @Override
    public void onTitleChanged(TerminalSession s) { }

    @Override
    public void onSessionFinished(TerminalSession s) {
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
