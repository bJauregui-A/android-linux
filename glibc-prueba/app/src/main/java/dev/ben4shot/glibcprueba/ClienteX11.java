package dev.ben4shot.glibcprueba;

import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.ServiceConnection;
import android.os.IBinder;
import android.os.Parcel;
import android.os.ParcelFileDescriptor;
import android.system.ErrnoException;
import android.system.Os;
import android.system.OsConstants;
import android.system.StructPollfd;
import android.util.Log;
import android.view.Surface;

import java.io.File;
import java.io.FileDescriptor;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

// Lado de la app de ServicioX11 (proceso :x11). Binder solo conecta y entrega la Surface; la entrada va por
// un socketpair SOCK_SEQPACKET con el mismo struct mensaje que lee el servidor (x11/ddx/android/android.h).
final class ClienteX11 {
    private static final String TAG = "X11";
    static final int CONECTAR = IBinder.FIRST_CALL_TRANSACTION;
    static final int VENTANA = IBinder.FIRST_CALL_TRANSACTION + 1;

    // Mismos valores que enum del android.h
    private static final int MSG_TECLA = 0, MSG_MOVER = 1, MSG_BOTON = 2, MSG_EJE = 3;
    private static final int MENSAJE = 20;

    private static ClienteX11 actual;

    private final Context app;
    private final Runnable alMorir;
    private ServiceConnection conexion;
    private IBinder servicio;
    private FileDescriptor entrada;
    private Surface ultima;     // la última que dio la vista, por si llega antes de terminar de conectar
    private boolean listo, cerrado;

    private ClienteX11(Context app, Runnable alMorir) {
        this.app = app;
        this.alMorir = alMorir;
    }

    // Un servidor que murió (la app se reinstaló o se mató) deja su socket y su lock: el supervisor de la sesión
    // vería "listo" un socket sin nadie detrás y los clientes recibirían "Connection refused".
    // Se llama antes de arrancar la sesión, cuando no hay servidor nuestro vivo.
    static synchronized void limpiarRestos(Context ctx) {
        if (actual != null) return;
        File base = new File(ctx.getFilesDir(), "x11");
        new File(base, ".X11-unix/X0").delete();
        new File(base, ".X0-lock").delete();
    }

    static synchronized ClienteX11 actual() {
        return actual;
    }

    // Arranca el servidor en un hilo (bindService responde en el hilo principal: no se puede esperar ahí).
    // Si el proceso :x11 muere, llama a alMorir (en un hilo de Binder).
    static synchronized ClienteX11 arrancar(Context ctx, String instanciaId, int ancho, int alto, int dpi,
                                           Surface surface, Runnable alMorir) {
        if (actual != null) return actual;
        ClienteX11 c = new ClienteX11(ctx.getApplicationContext(), alMorir);
        c.ultima = surface;
        actual = c;
        new Thread(() -> c.conectar(instanciaId, ancho, alto, dpi), "x11-conectar").start();
        return c;
    }

    private void conectar(String instanciaId, int ancho, int alto, int dpi) {
        CountDownLatch enlazado = new CountDownLatch(1);
        conexion = new ServiceConnection() {
            @Override
            public void onServiceConnected(ComponentName n, IBinder b) {
                servicio = b;
                enlazado.countDown();
            }

            @Override
            public void onServiceDisconnected(ComponentName n) { }
        };
        try {
            if (!app.bindService(new Intent(app, ServicioX11.class), conexion, Context.BIND_AUTO_CREATE)
                    || !enlazado.await(10, TimeUnit.SECONDS)) {
                throw new IllegalStateException("no se pudo enlazar con ServicioX11");
            }
            servicio.linkToDeath(() -> {
                Log.w(TAG, "el proceso :x11 murió");
                cerrar(app);
                if (alMorir != null) alMorir.run();
            }, 0);

            FileDescriptor[] par = { new FileDescriptor(), new FileDescriptor() };
            Os.socketpair(OsConstants.AF_UNIX, OsConstants.SOCK_SEQPACKET, 0, par[0], par[1]);
            Os.fcntlInt(par[0], OsConstants.F_SETFL, OsConstants.O_NONBLOCK);   // la escritura nunca bloquea
            enlazarSocket(instanciaId);
            Parcel data = Parcel.obtain(), reply = Parcel.obtain();
            try (ParcelFileDescriptor servidor = ParcelFileDescriptor.dup(par[1])) {
                data.writeStringArray(new String[] {":0", "-screen", "0", ancho + "x" + alto + "x24", "-dpi", String.valueOf(dpi)});
                servidor.writeToParcel(data, 0);
                servicio.transact(CONECTAR, data, reply, 0);
                reply.setDataPosition(0);
                if (reply.readInt() != 1) throw new IllegalStateException("ServicioX11 no arrancó el servidor");
            } finally {
                data.recycle();
                reply.recycle();
                Os.close(par[1]);
            }
            Surface s;
            synchronized (this) {
                entrada = par[0];
                listo = true;
                s = ultima;
            }
            if (s != null) ventana(s);
        } catch (Exception e) {
            Log.e(TAG, "conexión con el servidor X11", e);
            cerrar(app);
            if (alMorir != null) alMorir.run();
        }
    }

    // /tmp/.X11-unix/X0 de la instancia -> files/x11/.X11-unix/X0 (como wayland-0 en Wayland.iniciarPara).
    private void enlazarSocket(String instanciaId) throws ErrnoException {
        File dir = new File(SistemaLinux.raiz(app, instanciaId), "tmp/.X11-unix");
        dir.mkdirs();
        File enlace = new File(dir, "X0");
        enlace.delete();
        Os.symlink(new File(app.getFilesDir(), "x11/.X11-unix/X0").getAbsolutePath(), enlace.getAbsolutePath());
    }

    // null = la ventana se fue
    synchronized void ventana(Surface s) {
        ultima = s;
        if (!listo || cerrado) return;
        Parcel data = Parcel.obtain();
        try {
            data.writeInt(s != null ? 1 : 0);
            if (s != null) s.writeToParcel(data, 0);
            servicio.transact(VENTANA, data, null, IBinder.FLAG_ONEWAY);
        } catch (Exception e) {
            Log.w(TAG, "ventana", e);
        } finally {
            data.recycle();
        }
    }

    void tecla(int codigo, boolean pulsada) { enviar(MSG_TECLA, codigo, pulsada ? 1 : 0, 0, 0); }

    void mover(float x, float y) { enviar(MSG_MOVER, 0, 0, x, y); }

    void boton(int boton, boolean pulsado) { enviar(MSG_BOTON, boton, pulsado ? 1 : 0, 0, 0); }

    void eje(float dx, float dy) { enviar(MSG_EJE, 0, 0, dx, dy); }

    private synchronized void enviar(int tipo, int a, int b, float x, float y) {
        if (!listo || cerrado) return;
        ByteBuffer m = ByteBuffer.allocate(MENSAJE).order(ByteOrder.LITTLE_ENDIAN);
        m.putInt(tipo).putInt(a).putInt(b).putFloat(x).putFloat(y);
        try {
            try {
                Os.write(entrada, m.array(), 0, MENSAJE);
            } catch (ErrnoException e) {
                if (e.errno != OsConstants.EAGAIN) throw e;
                // socket lleno: un movimiento se descarta (el siguiente trae la posición nueva);
                // una tecla, un botón o la rueda no se pierden, se espera a que haya sitio
                if (tipo == MSG_MOVER) return;
                StructPollfd p = new StructPollfd();
                p.fd = entrada;
                p.events = (short) OsConstants.POLLOUT;
                Os.poll(new StructPollfd[] {p}, 1000);
                Os.write(entrada, m.array(), 0, MENSAJE);
            }
        } catch (ErrnoException | java.io.InterruptedIOException e) {
            Log.w(TAG, "entrada descartada (tipo " + tipo + ")", e);
        }
    }

    // Cierra la sesión X11: suelta el socket y el servicio (su proceso termina al irse el último enlace).
    static void cerrar(Context ctx) {
        ClienteX11 c;
        synchronized (ClienteX11.class) {
            c = actual;
            actual = null;
        }
        if (c == null) return;
        synchronized (c) {
            if (c.cerrado) return;
            c.cerrado = true;
            if (c.entrada != null) try { Os.close(c.entrada); } catch (ErrnoException ignorada) { }
        }
        try { c.app.unbindService(c.conexion); } catch (Exception ignorada) { }
        c.app.stopService(new Intent(c.app, ServicioX11.class));
    }
}
