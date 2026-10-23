package dev.ben4shot.glibcprueba;

import android.content.Context;
import android.net.ConnectivityManager;
import android.net.LinkAddress;
import android.net.LinkProperties;
import android.net.nsd.NsdManager;
import android.net.nsd.NsdServiceInfo;
import android.util.Log;

import java.io.File;
import java.io.FileWriter;
import java.net.InetAddress;
import java.util.ArrayDeque;

// Puertos de la depuracion inalambrica del propio telefono, para el adb de Arch (adb-conectar):
// adbd los anuncia por mDNS y cambian cada vez que se activa. Dentro de Linux `adb mdns` no ve
// nada (sin netlink no encuentra interfaces), asi que los busca Android (NsdManager) y los deja en
// /tmp/adb-puerto (conectar) y /tmp/adb-emparejar (vincular con codigo, solo con el dialogo abierto).
public final class PuertoAdb {
    private static final String TAG = "ADB";
    private static final String CONECTAR = "_adb-tls-connect._tcp";
    private static final String EMPAREJAR = "_adb-tls-pairing._tcp";
    private static boolean iniciado;
    public static volatile int ultimoPuerto = 0;

    private PuertoAdb() { }

    public static int obtenerPuerto() {
        return ultimoPuerto;
    }

    public static synchronized void iniciar(Context c) {
        if (iniciado) return;
        iniciado = true;
        Context app = c.getApplicationContext();
        NsdManager nsd = app.getSystemService(NsdManager.class);
        Resolutor r = new Resolutor(app, nsd);
        buscar(nsd, CONECTAR, "adb-puerto", r);
        buscar(nsd, EMPAREJAR, "adb-emparejar", r);
    }

    private static void buscar(NsdManager nsd, String tipo, String nombreArchivo, Resolutor r) {
        nsd.discoverServices(tipo, NsdManager.PROTOCOL_DNS_SD, new NsdManager.DiscoveryListener() {
            @Override
            public void onServiceFound(NsdServiceInfo s) { r.pedir(s, nombreArchivo); }

            @Override
            public void onServiceLost(NsdServiceInfo s) {
                if (tipo.equals(EMPAREJAR)) {
                    borrarArchivoGlobal(r.getContext(), "adb-emparejar");
                } else if (tipo.equals(CONECTAR)) {
                    ultimoPuerto = 0;
                    borrarArchivoGlobal(r.getContext(), "adb-puerto");
                }
            }

            @Override
            public void onDiscoveryStarted(String t) { Log.i(TAG, "buscando " + t); }

            @Override
            public void onDiscoveryStopped(String t) { }

            @Override
            public void onStartDiscoveryFailed(String t, int error) { Log.e(TAG, t + ": error " + error); }

            @Override
            public void onStopDiscoveryFailed(String t, int error) { }
        });
    }

    // resolveService admite uno a la vez (FAILURE_ALREADY_ACTIVE): cola.
    private static final class Resolutor {
        private final Context c;
        private final NsdManager nsd;
        private final ArrayDeque<Object[]> cola = new ArrayDeque<>();
        private boolean ocupado;

        Resolutor(Context c, NsdManager nsd) {
            this.c = c;
            this.nsd = nsd;
        }

        Context getContext() { return c; }

        synchronized void pedir(NsdServiceInfo s, String nombreArchivo) {
            cola.add(new Object[]{s, nombreArchivo});
            siguiente();
        }

        private synchronized void siguiente() {
            if (ocupado || cola.isEmpty()) return;
            Object[] p = cola.poll();
            String nombreArchivo = (String) p[1];
            ocupado = true;
            nsd.resolveService((NsdServiceInfo) p[0], new NsdManager.ResolveListener() {
                @Override
                public void onServiceResolved(NsdServiceInfo s) {
                    if (esPropia(c, s.getHost())) {
                        int puerto = s.getPort();
                        if ("adb-puerto".equals(nombreArchivo)) {
                            ultimoPuerto = puerto;
                        }
                        escribirArchivoGlobal(c, nombreArchivo, puerto);
                    }
                    listo();
                }

                @Override
                public void onResolveFailed(NsdServiceInfo s, int error) {
                    Log.e(TAG, "resolver " + s.getServiceName() + ": error " + error);
                    listo();
                }
            });
        }

        private synchronized void listo() {
            ocupado = false;
            siguiente();
        }
    }

    private static boolean esPropia(Context c, InetAddress host) {
        if (host == null) return false;
        if (host.isLoopbackAddress()) return true;
        ConnectivityManager cm = c.getSystemService(ConnectivityManager.class);
        for (android.net.Network n : cm.getAllNetworks()) {
            LinkProperties lp = cm.getLinkProperties(n);
            if (lp == null) continue;
            for (LinkAddress a : lp.getLinkAddresses()) {
                if (a.getAddress().equals(host)) return true;
            }
        }
        return false;
    }

    private static void escribir(File archivo, int puerto) {
        try {
            File parent = archivo.getParentFile();
            if (parent != null && !parent.exists()) parent.mkdirs();
            try (FileWriter w = new FileWriter(archivo)) {
                w.write(puerto + "\n");
            }
            archivo.setReadable(true, false);
            archivo.setWritable(true, false);
            Log.i(TAG, archivo.getAbsolutePath() + " = " + puerto);
        } catch (Exception e) {
            Log.e(TAG, archivo.getAbsolutePath(), e);
        }
    }

    private static void escribirArchivoGlobal(Context c, String nombreArchivo, int puerto) {
        // 1. En la raiz seleccionada actual
        try {
            File rSel = SistemaLinux.raizSeleccionada(c);
            escribir(new File(rSel, "tmp/" + nombreArchivo), puerto);
        } catch (Exception ignored) { }

        // 2. En todas las instancias existentes
        try {
            File dirInstancias = new File(c.getFilesDir(), "instancias");
            if (dirInstancias.isDirectory()) {
                File[] lista = dirInstancias.listFiles();
                if (lista != null) {
                    for (File inst : lista) {
                        if (inst.isDirectory()) {
                            escribir(new File(inst, "tmp/" + nombreArchivo), puerto);
                        }
                    }
                }
            }
        } catch (Exception ignored) { }

        // 3. En files/tmp directo
        try {
            escribir(new File(c.getFilesDir(), "tmp/" + nombreArchivo), puerto);
        } catch (Exception ignored) { }

        // 4. En /data/local/tmp para acceso directo de shell/adb
        try {
            escribir(new File("/data/local/tmp/" + nombreArchivo), puerto);
        } catch (Exception ignored) { }
    }

    private static void borrarArchivoGlobal(Context c, String nombreArchivo) {
        try {
            new File(SistemaLinux.raizSeleccionada(c), "tmp/" + nombreArchivo).delete();
        } catch (Exception ignored) { }
        try {
            File dirInstancias = new File(c.getFilesDir(), "instancias");
            if (dirInstancias.isDirectory()) {
                File[] lista = dirInstancias.listFiles();
                if (lista != null) {
                    for (File inst : lista) {
                        new File(inst, "tmp/" + nombreArchivo).delete();
                    }
                }
            }
        } catch (Exception ignored) { }
        try {
            new File(c.getFilesDir(), "tmp/" + nombreArchivo).delete();
        } catch (Exception ignored) { }
        try {
            new File("/data/local/tmp/" + nombreArchivo).delete();
        } catch (Exception ignored) { }
    }
}
