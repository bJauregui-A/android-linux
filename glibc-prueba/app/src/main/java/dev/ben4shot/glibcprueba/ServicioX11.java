package dev.ben4shot.glibcprueba;

import android.app.Service;
import android.content.Intent;
import android.os.Binder;
import android.os.IBinder;
import android.os.Parcel;
import android.os.ParcelFileDescriptor;
import android.system.Os;
import android.util.Log;
import android.view.Surface;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

// Servidor X11 (B11) en su propio proceso (":x11" en el manifiesto): xorg-server tiene mucho estado global
// y no se reinicia dentro del mismo proceso, así que cada sesión usa un proceso nuevo. Esta clase carga
// libxserver.so: la app nunca la toca (solo ClienteX11, que habla con ella por Binder).
// Binder solo conecta y entrega la Surface; la entrada llega por el socket que recibe en CONECTAR.
public class ServicioX11 extends Service {
    private static final String TAG = "X11";

    static {
        System.loadLibrary("xserver");
    }

    // argumentos del servidor; entrada = extremo del servidor del socketpair
    private static native void iniciar(String[] argumentos, int entrada);

    // surface null = la ventana se fue (el servidor suelta la anterior)
    private static native void ventana(Surface surface);

    private boolean iniciado;
    private Surface superficie;

    // "" para la ranura principal; las otras (ServicioX11B, C) dan su letra y usan files/x11/<letra>/ para sus sockets
    String ranura() {
        return "";
    }

    private final Binder binder = new Binder() {
        @Override
        protected boolean onTransact(int code, Parcel data, Parcel reply, int flags) {
            switch (code) {
                case ClienteX11.CONECTAR: {
                    String[] args = data.createStringArray();
                    ParcelFileDescriptor entrada = ParcelFileDescriptor.CREATOR.createFromParcel(data);
                    boolean ok = arrancar(args, entrada);
                    if (reply != null) reply.writeInt(ok ? 1 : 0);
                    return true;
                }
                case ClienteX11.VENTANA: {
                    // Cada envío es un Surface nuevo sobre la misma BufferQueue: el anterior se suelta ya (el servidor
                    // tiene su propia referencia), si no sigue conectado hasta el GC y el lock del nuevo falla.
                    Surface s = data.readInt() != 0 ? Surface.CREATOR.createFromParcel(data) : null;
                    ventana(s);
                    synchronized (ServicioX11.this) {
                        if (superficie != null) superficie.release();
                        superficie = s;
                    }
                    return true;
                }
            }
            return false;
        }
    };

    @Override
    public IBinder onBind(Intent intent) {
        return binder;
    }

    // El servidor no se reinicia dentro de su proceso: al irse el último enlace el proceso muere ya, no cuando Android
    // quiera. Si quedara vivo, la sesión siguiente se enlazaría a él y su aviso de muerte llegaría en plena sesión nueva.
    @Override
    public void onDestroy() {
        super.onDestroy();
        android.os.Process.killProcess(android.os.Process.myPid());
    }

    private synchronized boolean arrancar(String[] args, ParcelFileDescriptor entrada) {
        if (iniciado) return false;
        try {
            File base = new File(getFilesDir(), "x11");
            // lo que no cambia entre servidores se comparte; el socket, el lock, el log y el caché de teclado son de la ranura
            File propio = ranura().isEmpty() ? base : new File(base, ranura());
            File bin = new File(base, "bin");
            File sockets = new File(propio, ".X11-unix");
            bin.mkdirs();
            sockets.mkdirs();
            File xkm = new File(propio, "xkm");
            xkm.mkdirs();
            extraerXkb(base);
            // el servidor ejecuta <X11_XKB_BIN>/xkbcomp; nativeLibraryDir es lo único ejecutable y ahí se llama libxkbcomp.so
            // (el enlace es de todos: no se rehace si ya apunta ahí, otro servidor puede estar usándolo)
            File enlace = new File(bin, "xkbcomp");
            String destino = getApplicationInfo().nativeLibraryDir + "/libxkbcomp.so";
            if (!destino.equals(apuntaA(enlace))) {
                enlace.delete();
                Os.symlink(destino, enlace.getAbsolutePath());
            }
            Os.setenv("X11_UNIX_DIR", sockets.getAbsolutePath(), true);
            Os.setenv("X11_LOCK_DIR", propio.getAbsolutePath(), true);
            Os.setenv("X11_XKM_DIR", xkm.getAbsolutePath(), true);
            Os.setenv("X11_XKB_BIN", bin.getAbsolutePath(), true);
            Os.setenv("X11_LOG", new File(propio, "Xandroid.log").getAbsolutePath(), true);
            if (BuildConfig.DEBUG) Os.setenv("X11_CRASH_PASSTHRU", "1", true);
            Os.setenv("LD_LIBRARY_PATH", getApplicationInfo().nativeLibraryDir, true);
            String[] completos = new String[args.length + 2];
            System.arraycopy(args, 0, completos, 0, args.length);
            completos[args.length] = "-xkbdir";
            completos[args.length + 1] = new File(base, "xkb").getAbsolutePath();
            iniciar(completos, entrada.detachFd());
            iniciado = true;
            return true;
        } catch (Exception e) {
            Log.e(TAG, "no arrancó el servidor", e);
            return false;
        }
    }

    private static String apuntaA(File enlace) {
        try {
            return Os.readlink(enlace.getAbsolutePath());
        } catch (android.system.ErrnoException e) {
            return null;    // no existe o no es un enlace
        }
    }

    // Datos de teclado del APK (assets/x11-xkb.zip) a files/x11/xkb/, una vez por versión de la app.
    private void extraerXkb(File base) throws Exception {
        // varios servidores pueden arrancar a la vez (uno por instancia): el primero extrae, los demás esperan
        try (java.io.RandomAccessFile cerrojo = new java.io.RandomAccessFile(new File(base, "xkb.lock"), "rw");
             java.nio.channels.FileLock l = cerrojo.getChannel().lock()) {
            extraerXkbConCerrojo(base);
        }
    }

    private void extraerXkbConCerrojo(File base) throws Exception {
        File destino = new File(base, "xkb");
        File marca = new File(base, "xkb.version");
        long version = getPackageManager().getPackageInfo(getPackageName(), 0).lastUpdateTime;
        if (destino.isDirectory() && marca.isFile() && marca.lastModified() == version) return;
        try (InputStream in = getAssets().open("x11-xkb.zip"); ZipInputStream zip = new ZipInputStream(in)) {
            for (ZipEntry e; (e = zip.getNextEntry()) != null; ) {
                File f = new File(base, e.getName());
                if (!f.getCanonicalPath().startsWith(base.getCanonicalPath() + "/")) continue;
                if (e.isDirectory()) { f.mkdirs(); continue; }
                f.getParentFile().mkdirs();
                try (FileOutputStream out = new FileOutputStream(f)) {
                    byte[] b = new byte[8192];
                    for (int n; (n = zip.read(b)) > 0; ) out.write(b, 0, n);
                }
            }
        }
        marca.createNewFile();
        marca.setLastModified(version);
    }
}
