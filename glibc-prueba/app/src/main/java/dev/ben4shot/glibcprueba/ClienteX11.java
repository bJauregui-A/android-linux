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
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

// Lado de la app de ServicioX11 (un proceso :x11 por instancia que corre a la vez). Binder solo conecta y entrega la
// Surface; la entrada va por un socketpair SOCK_SEQPACKET con el mismo struct mensaje que lee el servidor
// (x11/ddx/android/android.h).
final class ClienteX11 {
    private static final String TAG = "X11";
    static final int CONECTAR = IBinder.FIRST_CALL_TRANSACTION;
    static final int VENTANA = IBinder.FIRST_CALL_TRANSACTION + 1;

    // Mismos valores que enum del android.h
    private static final int MSG_TECLA = 0, MSG_MOVER = 1, MSG_BOTON = 2, MSG_EJE = 3;
    private static final int MENSAJE = 20;

    // Una ranura por servicio declarado en el manifiesto: ServicioX11 (:x11), ServicioX11B (:x11b), ServicioX11C (:x11c).
    private static final Class<?>[] SERVICIOS = {ServicioX11.class, ServicioX11B.class, ServicioX11C.class};
    private static final String[] LETRAS = {"", "b", "c"};
    private static final RanurasX11 ranuras = new RanurasX11(SERVICIOS.length);
    private static final Map<String, ClienteX11> clientes = new HashMap<>();
    // El Binder del proceso que usó cada ranura antes: la siguiente espera a que haya muerto.
    private static final IBinder[] anteriores = new IBinder[SERVICIOS.length];
    private static final int ESPERA_ANTERIOR_MS = 5000;
    // Display de todos los servidores (cada uno en su carpeta). No es el :0: el Xwayland de una sesión Wayland escucha en un
    // socket abstracto (@/tmp/.X11-unix/X0) que ven todos los procesos de la app, y libxcb prueba el abstracto antes que el
    // archivo: un cliente con DISPLAY=:0 acababa en el Xwayland de otra instancia.
    private static final int DISPLAY_X11 = 10;
    private static final int INTENTOS_ENLACE = 3;
    private static final int ESPERA_ENLACE_S = 4;

    private final Context app;
    private final String instancia;
    private final int ranura;
    private volatile Runnable alMorir;
    private ServiceConnection conexion;
    private IBinder servicio;
    private FileDescriptor entrada;
    private Surface ultima;     // la última que dio la vista, por si llega antes de terminar de conectar
    private boolean listo, cerrado;

    private ClienteX11(Context app, String instancia, int ranura, Runnable alMorir) {
        this.app = app;
        this.instancia = instancia;
        this.ranura = ranura;
        this.alMorir = alMorir;
    }

    private static File carpetaDe(Context ctx, int ranura) {
        File base = new File(ctx.getFilesDir(), "x11");
        return LETRAS[ranura].isEmpty() ? base : new File(base, LETRAS[ranura]);
    }

    // Un servidor que murió (la app se reinstaló o se mató) deja su socket y su lock: el supervisor de la sesión
    // vería "listo" un socket sin nadie detrás y los clientes recibirían "Connection refused".
    // Solo se limpian las ranuras sin dueño: las demás tienen un servidor nuestro vivo.
    static synchronized void limpiarRestos(Context ctx) {
        for (int r = 0; r < SERVICIOS.length; r++) {
            if (ranuras.dueno(r) != null) continue;
            File carpeta = carpetaDe(ctx, r);
            new File(carpeta, ".X11-unix/X" + DISPLAY_X11).delete();
            new File(carpeta, ".X" + DISPLAY_X11 + "-lock").delete();
        }
    }

    // El cliente de esa instancia, o null si no tiene servidor.
    static synchronized ClienteX11 de(String instancia) {
        return instancia == null ? null : clientes.get(instancia);
    }

    // Arranca el servidor de la instancia en un hilo (bindService responde en el hilo principal: no se puede esperar
    // ahí). Si la instancia ya tiene servidor, lo devuelve y solo cambia a quién avisar si muere.
    // Si el proceso :x11 muere, llama a alMorir (en un hilo de Binder).
    static synchronized ClienteX11 arrancar(Context ctx, String instanciaId, int ancho, int alto, int dpi,
                                           Surface surface, Runnable alMorir) {
        ClienteX11 existente = clientes.get(instanciaId);
        if (existente != null) {
            existente.alMorir = alMorir;
            return existente;
        }
        int r = ranuras.asignar(instanciaId);
        if (r < 0) {
            // todas las ranuras ocupadas: se cierra el servidor de la instancia que lleva más tiempo
            String vieja = ranuras.masAntiguaExcepto(instanciaId);
            ClienteX11 desalojado = vieja == null ? null : clientes.get(vieja);
            Log.w(TAG, "sin ranuras libres, se cierra el servidor de " + vieja);
            if (vieja != null) cerrar(ctx, vieja);
            if (desalojado != null && desalojado.alMorir != null) desalojado.alMorir.run();
            r = ranuras.asignar(instanciaId);
            if (r < 0) return null;
        }
        ClienteX11 c = new ClienteX11(ctx.getApplicationContext(), instanciaId, r, alMorir);
        c.ultima = surface;
        clientes.put(instanciaId, c);
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
            esperarProcesoAnterior();
            // Enlazar justo cuando el proceso anterior de la ranura acaba de morir a veces no arranca uno nuevo (Android
            // lo da por enlazado a un proceso que ya no está): si no llega en unos segundos, se suelta y se reintenta.
            boolean ok = false;
            for (int intento = 1; intento <= INTENTOS_ENLACE && !ok; intento++) {
                if (intento > 1) {
                    Log.w(TAG, "ServicioX11 no respondió, reintento " + intento);
                    try { app.unbindService(conexion); } catch (Exception ignorada) { }
                    Thread.sleep(300);
                }
                ok = app.bindService(new Intent(app, SERVICIOS[ranura]), conexion, Context.BIND_AUTO_CREATE)
                        && enlazado.await(ESPERA_ENLACE_S, TimeUnit.SECONDS);
            }
            if (!ok) throw new IllegalStateException("no se pudo enlazar con ServicioX11");
            servicio.linkToDeath(() -> {
                Log.w(TAG, "el proceso :x11" + LETRAS[ranura] + " murió (" + instancia + ")");
                alMorirElServidor();
            }, 0);

            FileDescriptor[] par = { new FileDescriptor(), new FileDescriptor() };
            Os.socketpair(OsConstants.AF_UNIX, OsConstants.SOCK_SEQPACKET, 0, par[0], par[1]);
            Os.fcntlInt(par[0], OsConstants.F_SETFL, OsConstants.O_NONBLOCK);   // la escritura nunca bloquea
            enlazarSocket(instanciaId);
            Parcel data = Parcel.obtain(), reply = Parcel.obtain();
            try (ParcelFileDescriptor servidor = ParcelFileDescriptor.dup(par[1])) {
                data.writeStringArray(new String[] {":" + DISPLAY_X11, "-screen", "0", ancho + "x" + alto + "x24", "-dpi", String.valueOf(dpi)});
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
            alMorirElServidor();
        }
    }

    // Solo si este cliente sigue siendo el de su instancia: el aviso de muerte de un :x11 que ya se cerró llega tarde,
    // cuando puede haber uno nuevo, y cerrar la instancia cerraría ese en lugar de este (te devolvía al inicio al reabrir rápido).
    private void alMorirElServidor() {
        synchronized (ClienteX11.class) {
            if (clientes.get(instancia) != this) return;
        }
        cerrar(app, instancia);
        Runnable r = alMorir;
        if (r != null) r.run();
    }

    // El proceso anterior de esta ranura tarda en irse tras cerrar(): hasta que muere no se arranca otro servidor.
    private void esperarProcesoAnterior() throws InterruptedException {
        IBinder viejo;
        synchronized (ClienteX11.class) {
            viejo = anteriores[ranura];
        }
        for (int ms = 0; viejo != null && viejo.pingBinder() && ms < ESPERA_ANTERIOR_MS; ms += 50) {
            Thread.sleep(50);
        }
        synchronized (ClienteX11.class) {
            if (anteriores[ranura] == viejo) anteriores[ranura] = null;
        }
        if (viejo != null) {
            Thread.sleep(250);   // que Android termine de dar de baja el proceso antes de enlazar otro
        }
    }

    // /tmp/.X11-unix/X10 de la instancia -> files/x11/[<letra>/].X11-unix/X10 (como wayland-0 -> files/wayland/wayland-0 en Wayland.iniciarPara).
    private void enlazarSocket(String instanciaId) throws ErrnoException {
        File dir = new File(SistemaLinux.raiz(app, instanciaId), "tmp/.X11-unix");
        dir.mkdirs();
        File enlace = new File(dir, "X" + DISPLAY_X11);
        enlace.delete();
        Os.symlink(new File(carpetaDe(app, ranura), ".X11-unix/X" + DISPLAY_X11).getAbsolutePath(), enlace.getAbsolutePath());
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

    // Cierra el servidor de una instancia: suelta el socket y el servicio (su proceso termina al irse el último enlace).
    // Las demás instancias no se tocan. instanciaId null cierra todos.
    static void cerrar(Context ctx, String instanciaId) {
        if (instanciaId == null) {
            List<String> todas;
            synchronized (ClienteX11.class) {
                todas = new ArrayList<>(clientes.keySet());
            }
            for (String id : todas) cerrar(ctx, id);
            return;
        }
        ClienteX11 c;
        synchronized (ClienteX11.class) {
            c = clientes.remove(instanciaId);
            if (c == null) return;
            ranuras.liberar(instanciaId);
            if (c.servicio != null) anteriores[c.ranura] = c.servicio;
        }
        synchronized (c) {
            if (c.cerrado) return;
            c.cerrado = true;
            if (c.entrada != null) try { Os.close(c.entrada); } catch (ErrnoException ignorada) { }
        }
        try { c.app.unbindService(c.conexion); } catch (Exception ignorada) { }
        c.app.stopService(new Intent(c.app, SERVICIOS[c.ranura]));
    }
}
