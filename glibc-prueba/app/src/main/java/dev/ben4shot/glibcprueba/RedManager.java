package dev.ben4shot.glibcprueba;

import android.content.Context;
import android.content.SharedPreferences;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

// Gestor de red local y reenvío de puertos (Port Forwarding):
// Permite que puertos externos del teléfono (ej: 8022, 8080) se redirijan dinámicamente
// a entornos específicos e IPs/puertos internos sin requerir permisos root.
public final class RedManager {
    private static final String TAG = "RED_MANAGER";
    private static final String PREF_NAME = "red_config";
    private static final String PREF_REGLAS = "port_forward_reglas";
    private static final String PREF_HABILITADO = "port_forward_habilitado";
    private static final String PREF_SUBRED = "subred_virtual";
    public static final String DEFAULT_SUBRED = "10.0.0.0/24";

    public static String obtenerSubred(Context c) {
        return c.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
                .getString(PREF_SUBRED, DEFAULT_SUBRED);
    }

    public static void setSubred(Context c, String subred) {
        c.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
                .edit()
                .putString(PREF_SUBRED, subred.trim())
                .apply();
        actualizar(c);
    }

    public static String ipParaInstancia(Context c, String instanciaId) {
        String sub = obtenerSubred(c);
        String prefix = sub.contains("/") ? sub.substring(0, sub.lastIndexOf('.')) : "10.0.0";
        if ("gateway".equals(instanciaId) || "host".equals(instanciaId)) {
            return prefix + ".1";
        }
        List<SistemaLinux.Instancia> list = SistemaLinux.listarInstancias(c);
        int idx = 2;
        for (SistemaLinux.Instancia inst : list) {
            if (inst.id.equals(instanciaId)) {
                return prefix + "." + idx;
            }
            idx++;
        }
        return prefix + ".2";
    }

    public static class Regla {
        public final String id;
        public final int puertoExterno;
        public final String instanciaId;
        public final int puertoInterno;
        public boolean activa;

        public Regla(String id, int puertoExterno, String instanciaId, int puertoInterno, boolean activa) {
            this.id = id;
            this.puertoExterno = puertoExterno;
            this.instanciaId = instanciaId;
            this.puertoInterno = puertoInterno;
            this.activa = activa;
        }

        public JSONObject aJson() throws JSONException {
            JSONObject o = new JSONObject();
            o.put("id", id);
            o.put("puertoExterno", puertoExterno);
            o.put("instanciaId", instanciaId);
            o.put("puertoInterno", puertoInterno);
            o.put("activa", activa);
            return o;
        }

        public static Regla deJson(JSONObject o) {
            return new Regla(
                    o.optString("id", String.valueOf(System.currentTimeMillis())),
                    o.optInt("puertoExterno", 8022),
                    o.optString("instanciaId", "arch-principal"),
                    o.optInt("puertoInterno", 22),
                    o.optBoolean("activa", true)
            );
        }
    }

    private static final Map<Integer, ServidorForward> servidores = new ConcurrentHashMap<>();
    private static ExecutorService poolPipes;

    private static class ServidorForward {
        final Regla regla;
        final ServerSocket serverSocket;
        final Thread threadAceptador;

        ServidorForward(Regla regla, ServerSocket ss, Thread t) {
            this.regla = regla;
            this.serverSocket = ss;
            this.threadAceptador = t;
        }

        void cerrar() {
            try {
                serverSocket.close();
            } catch (Exception ignorada) { }
            threadAceptador.interrupt();
        }
    }

    private RedManager() { }

    public static synchronized List<Regla> listarReglas(Context c) {
        SharedPreferences p = c.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE);
        String raw = p.getString(PREF_REGLAS, null);
        List<Regla> res = new ArrayList<>();
        if (raw != null && !raw.trim().isEmpty()) {
            try {
                JSONArray arr = new JSONArray(raw);
                for (int i = 0; i < arr.length(); i++) {
                    res.add(Regla.deJson(arr.getJSONObject(i)));
                }
            } catch (JSONException e) {
                Log.w(TAG, "error leyendo reglas json", e);
            }
        } else {
            // Regla inicial sugerida: puerto 8022 al primer entorno disponible
            SistemaLinux.Instancia sel = SistemaLinux.instanciaSeleccionada(c);
            String targetId = sel != null ? sel.id : "arch-principal";
            Regla def = new Regla("ssh-default", 8022, targetId, 22, true);
            res.add(def);
            guardarReglas(c, res);
        }
        return res;
    }

    public static synchronized void guardarReglas(Context c, List<Regla> lista) {
        JSONArray arr = new JSONArray();
        for (Regla r : lista) {
            try {
                arr.put(r.aJson());
            } catch (JSONException ignorada) { }
        }
        c.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
                .edit()
                .putString(PREF_REGLAS, arr.toString())
                .apply();
    }

    public static boolean esHabilitado(Context c) {
        return c.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
                .getBoolean(PREF_HABILITADO, true);
    }

    public static void setHabilitado(Context c, boolean hab) {
        c.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(PREF_HABILITADO, hab)
                .apply();
        actualizar(c);
    }

    public static synchronized void actualizar(Context c) {
        if (poolPipes == null || poolPipes.isShutdown()) {
            poolPipes = Executors.newCachedThreadPool();
        }
        boolean generalHabilitado = esHabilitado(c);
        List<Regla> reglas = listarReglas(c);

        if (!generalHabilitado) {
            detenerTodo();
            return;
        }

        // Cerrar servidores cuyos puertos ya no existan o cambiaron de destino
        for (Map.Entry<Integer, ServidorForward> entry : new ArrayList<>(servidores.entrySet())) {
            int port = entry.getKey();
            ServidorForward sf = entry.getValue();
            boolean vigente = false;
            for (Regla r : reglas) {
                if (r.puertoExterno == port && r.activa && r.instanciaId.equals(sf.regla.instanciaId)
                        && r.puertoInterno == sf.regla.puertoInterno) {
                    vigente = true;
                    break;
                }
            }
            if (!vigente) {
                sf.cerrar();
                servidores.remove(port);
            }
        }

        // Levantar servidores para reglas activas que aún no están escuchando
        for (Regla r : reglas) {
            if (!r.activa) continue;
            if (servidores.containsKey(r.puertoExterno)) continue;

            iniciarServidorParaRegla(r);
        }
    }

    private static void iniciarServidorParaRegla(Regla r) {
        try {
            ServerSocket ss = new ServerSocket(r.puertoExterno, 50, InetAddress.getByName("0.0.0.0"));
            Thread t = new Thread(() -> bucleAceptar(r, ss), "pforward-" + r.puertoExterno);
            ServidorForward sf = new ServidorForward(r, ss, t);
            servidores.put(r.puertoExterno, sf);
            t.start();
            Log.i(TAG, "Port forward escuchando en :" + r.puertoExterno + " -> " + r.instanciaId + ":" + r.puertoInterno);
        } catch (IOException e) {
            Log.w(TAG, "No se pudo enlazar puerto externo " + r.puertoExterno + ": " + e.getMessage());
        }
    }

    private static void bucleAceptar(Regla r, ServerSocket ss) {
        while (!Thread.currentThread().isInterrupted() && !ss.isClosed()) {
            try {
                Socket cliente = ss.accept();
                if (poolPipes != null && !poolPipes.isShutdown()) {
                    poolPipes.execute(() -> procesarConexion(r, cliente));
                } else {
                    cliente.close();
                }
            } catch (IOException e) {
                if (ss.isClosed()) break;
                Log.w(TAG, "error en accept puerto " + r.puertoExterno + ": " + e.getMessage());
            }
        }
    }

    private static void procesarConexion(Regla r, Socket cliente) {
        Socket destino = null;
        try {
            // Conectar al puerto local interno del host
            // (Si el entorno destino corre sshd en 8022 o su propio puerto, redirige directamente)
            destino = new Socket("127.0.0.1", r.puertoInterno == 22 ? 8022 : r.puertoInterno);
            Socket finalDestino = destino;

            if (poolPipes != null && !poolPipes.isShutdown()) {
                poolPipes.execute(() -> reenviarFlujo(cliente, finalDestino));
                reenviarFlujo(destino, cliente);
            }
        } catch (Exception e) {
            Log.w(TAG, "Fallo de conexión forward a " + r.instanciaId + ":" + r.puertoInterno + " - " + e.getMessage());
            try { cliente.close(); } catch (Exception ignored) { }
            if (destino != null) {
                try { destino.close(); } catch (Exception ignored) { }
            }
        }
    }

    private static void reenviarFlujo(Socket origen, Socket destino) {
        try (InputStream in = origen.getInputStream();
             OutputStream out = destino.getOutputStream()) {
            byte[] buf = new byte[16384];
            int n;
            while ((n = in.read(buf)) != -1) {
                out.write(buf, 0, n);
                out.flush();
            }
        } catch (Exception ignorada) {
        } finally {
            try { origen.close(); } catch (Exception ignored) { }
            try { destino.close(); } catch (Exception ignored) { }
        }
    }

    public static synchronized void detenerTodo() {
        for (ServidorForward sf : servidores.values()) {
            sf.cerrar();
        }
        servidores.clear();
        if (poolPipes != null) {
            poolPipes.shutdownNow();
            poolPipes = null;
        }
    }
}
