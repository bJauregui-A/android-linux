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
                case ClienteX11.VENTANA:
                    ventana(data.readInt() != 0 ? Surface.CREATOR.createFromParcel(data) : null);
                    return true;
            }
            return false;
        }
    };

    @Override
    public IBinder onBind(Intent intent) {
        return binder;
    }

    private synchronized boolean arrancar(String[] args, ParcelFileDescriptor entrada) {
        if (iniciado) return false;
        try {
            File base = new File(getFilesDir(), "x11");
            File bin = new File(base, "bin");
            File sockets = new File(base, ".X11-unix");
            bin.mkdirs();
            sockets.mkdirs();
            File xkm = new File(base, "xkm");
            xkm.mkdirs();
            extraerXkb(base);
            // el servidor ejecuta <X11_XKB_BIN>/xkbcomp; nativeLibraryDir es lo único ejecutable y ahí se llama libxkbcomp.so
            File enlace = new File(bin, "xkbcomp");
            enlace.delete();
            Os.symlink(getApplicationInfo().nativeLibraryDir + "/libxkbcomp.so", enlace.getAbsolutePath());
            Os.setenv("X11_UNIX_DIR", sockets.getAbsolutePath(), true);
            Os.setenv("X11_LOCK_DIR", base.getAbsolutePath(), true);
            Os.setenv("X11_XKM_DIR", xkm.getAbsolutePath(), true);
            Os.setenv("X11_XKB_BIN", bin.getAbsolutePath(), true);
            Os.setenv("X11_LOG", new File(base, "Xandroid.log").getAbsolutePath(), true);
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

    // Datos de teclado del APK (assets/x11-xkb.zip) a files/x11/xkb/, una vez por versión de la app.
    private void extraerXkb(File base) throws Exception {
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
