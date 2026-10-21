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

// Puertos de la depuración inalámbrica del propio teléfono, para el adb de Arch (adb-conectar):
// adbd los anuncia por mDNS y cambian cada vez que se activa. Dentro de Linux `adb mdns` no ve
// nada (sin netlink no encuentra interfaces), así que los busca Android (NsdManager) y los deja en
// /tmp/adb-puerto (conectar) y /tmp/adb-emparejar (vincular con código, solo con el diálogo abierto).
final class PuertoAdb {
    private static final String TAG = "ADB";
    private static final String CONECTAR = "_adb-tls-connect._tcp";
    private static final String EMPAREJAR = "_adb-tls-pairing._tcp";
    private static boolean iniciado;

    private PuertoAdb() { }

    static synchronized void iniciar(Context c) {
        if (iniciado) return;
        iniciado = true;
        Context app = c.getApplicationContext();
        NsdManager nsd = app.getSystemService(NsdManager.class);
        File tmp = new File(SistemaLinux.raizSeleccionada(app), "tmp");
        Resolutor r = new Resolutor(app, nsd);
        buscar(nsd, CONECTAR, new File(tmp, "adb-puerto"), r);
        buscar(nsd, EMPAREJAR, new File(tmp, "adb-emparejar"), r);
    }

    private static void buscar(NsdManager nsd, String tipo, File archivo, Resolutor r) {
        nsd.discoverServices(tipo, NsdManager.PROTOCOL_DNS_SD, new NsdManager.DiscoveryListener() {
            @Override
            public void onServiceFound(NsdServiceInfo s) { r.pedir(s, archivo); }

            @Override
            public void onServiceLost(NsdServiceInfo s) {
                // El de vincular desaparece al cerrar el diálogo; el de conectar se reescribe
                // cuando vuelve a aparecer (adb-conectar prueba y cae al escaneo si no sirve).
                if (tipo.equals(EMPAREJAR)) archivo.delete();
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

        synchronized void pedir(NsdServiceInfo s, File archivo) {
            cola.add(new Object[]{s, archivo});
            siguiente();
        }

        private synchronized void siguiente() {
            if (ocupado || cola.isEmpty()) return;
            Object[] p = cola.poll();
            File archivo = (File) p[1];
            ocupado = true;
            nsd.resolveService((NsdServiceInfo) p[0], new NsdManager.ResolveListener() {
                @Override
                public void onServiceResolved(NsdServiceInfo s) {
                    // En la red puede haber otros teléfonos con depuración: solo el propio
                    if (esPropia(c, s.getHost())) escribir(archivo, s.getPort());
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
        archivo.getParentFile().mkdirs();
        try (FileWriter w = new FileWriter(archivo)) {
            w.write(puerto + "\n");
            Log.i(TAG, archivo.getName() + " = " + puerto);
        } catch (Exception e) {
            Log.e(TAG, archivo.getName(), e);
        }
    }
}
