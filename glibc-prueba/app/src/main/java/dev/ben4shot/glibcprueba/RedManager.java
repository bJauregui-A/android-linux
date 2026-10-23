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
import java.util.concurrent.SynchronousQueue;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;

// Gestor de red local y reenvío de puertos (Port Forwarding):
// Permite que puertos externos del teléfono (ej: 8022, 8080) se redirijan dinámicamente
// a entornos específicos e IPs/puertos internos sin requerir permisos root.
public final class RedManager {
    private static final String TAG = "RED_MANAGER";
    private static final String PREF_NAME = "red_config";
    private static final String PREF_REGLAS = "port_forward_reglas";
    private static final String PREF_HABILITADO = "port_forward_habilitado";
    private static final String PREF_SUBRED = "subred_virtual";
    private static final String PREF_SUBREDES = "subredes_lista";
    private static final String PREF_ASIGNACIONES = "subred_asignaciones";
    public static final String PREF_PROXY22_HABILITADO = "proxy22_habilitado";
    public static final String PREF_PROXY22_TARGET = "proxy22_target";
    public static final String ARCHIVO_TARGET_PROXY22 = "/data/local/tmp/ssh-proxy-target";
    public static final String ARCHIVO_CONF_PROXY_PORTS = "/data/local/tmp/proxy-ports.conf";
    public static final String DEFAULT_SUBRED = "10.0.0.0/24";

    public static class Subred {
        public final String id;
        public String nombre;
        public String cidr;

        public Subred(String id, String nombre, String cidr) {
            this.id = id;
            this.nombre = nombre;
            this.cidr = cidr;
        }

        public JSONObject aJson() throws JSONException {
            JSONObject o = new JSONObject();
            o.put("id", id);
            o.put("nombre", nombre);
            o.put("cidr", cidr);
            return o;
        }

        public static Subred deJson(JSONObject o) {
            return new Subred(
                    o.optString("id", "sub_" + System.currentTimeMillis()),
                    o.optString("nombre", "Subred Principal"),
                    o.optString("cidr", DEFAULT_SUBRED)
            );
        }
    }

    public static class AsignacionIp {
        public final String instanciaId;
        public String subredId;
        public String ip;

        public AsignacionIp(String instanciaId, String subredId, String ip) {
            this.instanciaId = instanciaId;
            this.subredId = subredId;
            this.ip = ip;
        }

        public JSONObject aJson() throws JSONException {
            JSONObject o = new JSONObject();
            o.put("instanciaId", instanciaId);
            o.put("subredId", subredId);
            o.put("ip", ip);
            return o;
        }

        public static AsignacionIp deJson(JSONObject o) {
            return new AsignacionIp(
                    o.optString("instanciaId", ""),
                    o.optString("subredId", ""),
                    o.optString("ip", "")
            );
        }
    }

    public static synchronized List<Subred> listarSubredes(Context c) {
        SharedPreferences p = c.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE);
        String raw = p.getString(PREF_SUBREDES, null);
        List<Subred> res = new ArrayList<>();
        if (raw != null && !raw.trim().isEmpty()) {
            try {
                JSONArray arr = new JSONArray(raw);
                for (int i = 0; i < arr.length(); i++) {
                    res.add(Subred.deJson(arr.getJSONObject(i)));
                }
            } catch (JSONException e) {
                Log.w(TAG, "error leyendo subredes json", e);
            }
        }
        if (res.isEmpty()) {
            String legado = obtenerSubred(c);
            Subred def = new Subred("sub_default", "Subred Principal", legado);
            res.add(def);
            guardarSubredes(c, res);
        }
        return res;
    }

    public static synchronized void guardarSubredes(Context c, List<Subred> lista) {
        JSONArray arr = new JSONArray();
        for (Subred s : lista) {
            try {
                arr.put(s.aJson());
            } catch (JSONException ignorada) { }
        }
        c.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
                .edit()
                .putString(PREF_SUBREDES, arr.toString())
                .apply();
    }

    public static synchronized Subred agregarSubred(Context c, String nombre, String cidr) {
        List<Subred> list = listarSubredes(c);
        Subred s = new Subred("sub_" + System.currentTimeMillis(), nombre, cidr.trim());
        list.add(s);
        guardarSubredes(c, list);
        return s;
    }

    public static synchronized void eliminarSubred(Context c, String id) {
        List<Subred> list = listarSubredes(c);
        if (list.size() <= 1) return; // Mantener al menos una
        list.removeIf(s -> s.id.equals(id));
        guardarSubredes(c, list);
    }

    public static synchronized Map<String, AsignacionIp> listarAsignaciones(Context c) {
        SharedPreferences p = c.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE);
        String raw = p.getString(PREF_ASIGNACIONES, null);
        Map<String, AsignacionIp> res = new ConcurrentHashMap<>();
        if (raw != null && !raw.trim().isEmpty()) {
            try {
                JSONArray arr = new JSONArray(raw);
                for (int i = 0; i < arr.length(); i++) {
                    AsignacionIp asig = AsignacionIp.deJson(arr.getJSONObject(i));
                    if (!asig.instanciaId.isEmpty()) {
                        res.put(asig.instanciaId, asig);
                    }
                }
            } catch (JSONException e) {
                Log.w(TAG, "error leyendo asignaciones json", e);
            }
        }
        return res;
    }

    public static synchronized void guardarAsignaciones(Context c, Map<String, AsignacionIp> map) {
        JSONArray arr = new JSONArray();
        for (AsignacionIp asig : map.values()) {
            try {
                arr.put(asig.aJson());
            } catch (JSONException ignorada) { }
        }
        c.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
                .edit()
                .putString(PREF_ASIGNACIONES, arr.toString())
                .apply();
    }

    public static synchronized void asignarIp(Context c, String instanciaId, String subredId, String ip) {
        Map<String, AsignacionIp> map = listarAsignaciones(c);
        AsignacionIp asig = new AsignacionIp(instanciaId, subredId, ip.trim());
        map.put(instanciaId, asig);
        guardarAsignaciones(c, map);

        // Escribir en etc/virtual-ip dentro de la instancia
        escribirVirtualIp(c, instanciaId, ip.trim());
    }

    public static void escribirVirtualIp(Context c, String instanciaId, String ipCompleta) {
        try {
            java.io.File raiz = SistemaLinux.raiz(c, instanciaId);
            if (raiz != null && raiz.isDirectory()) {
                java.io.File dirEtc = new java.io.File(raiz, "etc");
                dirEtc.mkdirs();
                java.io.File vip = new java.io.File(dirEtc, "virtual-ip");
                try (java.io.FileWriter fw = new java.io.FileWriter(vip, false)) {
                    fw.write(ipCompleta + "\n");
                }
                Log.i(TAG, "Escrito " + vip.getAbsolutePath() + ": " + ipCompleta);
            }
        } catch (Exception e) {
            Log.w(TAG, "Error escribiendo etc/virtual-ip para " + instanciaId, e);
        }
        actualizarHosts(c);
    }

    public static void registrarIpActiva(Context c, String instanciaId) {
        try {
            String ip = ipParaInstancia(c, instanciaId);
            if (ip.contains("/")) ip = ip.substring(0, ip.indexOf('/'));
            java.io.File dir = new java.io.File(c.getFilesDir(), "ips");
            dir.mkdirs();
            java.io.File f = new java.io.File(dir, ip.trim());
            f.createNewFile();
            actualizarHosts(c);
        } catch (Exception ignored) { }
    }

    public static void desregistrarIpActiva(Context c, String instanciaId) {
        try {
            String ip = ipParaInstancia(c, instanciaId);
            if (ip.contains("/")) ip = ip.substring(0, ip.indexOf('/'));
            java.io.File dir = new java.io.File(c.getFilesDir(), "ips");
            java.io.File f = new java.io.File(dir, ip.trim());
            f.delete();
            actualizarHosts(c);
        } catch (Exception ignored) { }
    }

    public static void sincronizarIpsActivas(Context c, Iterable<String> instanciasActivas) {
        try {
            java.io.File dir = new java.io.File(c.getFilesDir(), "ips");
            dir.mkdirs();
            java.io.File[] files = dir.listFiles();
            if (files != null) {
                for (java.io.File f : files) f.delete();
            }
            if (instanciasActivas != null) {
                for (String id : instanciasActivas) {
                    String ip = ipParaInstancia(c, id);
                    if (ip.contains("/")) ip = ip.substring(0, ip.indexOf('/'));
                    new java.io.File(dir, ip.trim()).createNewFile();
                }
            }
            actualizarHosts(c);
        } catch (Exception ignored) { }
    }

    public static void actualizarHosts(Context c) {
        try {
            Map<String, AsignacionIp> asigs = listarAsignaciones(c);
            StringBuilder sb = new StringBuilder();
            sb.append("127.0.0.1\tlocalhost\n");
            sb.append("::1\tlocalhost\n");
            sb.append("10.0.0.1\tgateway host\n");
            for (AsignacionIp asig : asigs.values()) {
                String ip = asig.ip;
                if (ip != null && !ip.trim().isEmpty()) {
                    if (ip.contains("/")) ip = ip.substring(0, ip.indexOf('/'));
                    sb.append(ip.trim()).append("\t").append(asig.instanciaId).append("\n");
                }
            }
            String content = sb.toString();

            List<SistemaLinux.Instancia> list = SistemaLinux.listarInstancias(c);
            for (SistemaLinux.Instancia inst : list) {
                java.io.File raiz = SistemaLinux.raiz(c, inst.id);
                if (raiz != null && raiz.isDirectory()) {
                    java.io.File etc = new java.io.File(raiz, "etc");
                    if (etc.isDirectory()) {
                        java.io.File hosts = new java.io.File(etc, "hosts");
                        try (java.io.FileWriter fw = new java.io.FileWriter(hosts, false)) {
                            fw.write(content);
                        } catch (Exception ignored) { }
                    }
                }
            }
        } catch (Exception ignored) { }
    }

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
        Map<String, AsignacionIp> asigs = listarAsignaciones(c);
        AsignacionIp asig = asigs.get(instanciaId);
        if (asig != null && asig.ip != null && !asig.ip.trim().isEmpty()) {
            return asig.ip.trim();
        }

        // Sugerir IP determinista basada en la subred
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
            // Regla inicial sugerida desactivada por defecto para no competir con sshd directo en 8022
            SistemaLinux.Instancia sel = SistemaLinux.instanciaSeleccionada(c);
            String targetId = sel != null ? sel.id : "arch-principal";
            Regla def = new Regla("ssh-default", 2222, targetId, 22, false);
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
        actualizarProxy22Target(c);
        sincronizarProxyPortsConf(c);
        if (poolPipes == null || poolPipes.isShutdown()) {
            poolPipes = new ThreadPoolExecutor(
                    2, 16, 60L, TimeUnit.SECONDS,
                    new SynchronousQueue<>(),
                    new ThreadPoolExecutor.DiscardPolicy()
            );
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

            iniciarServidorParaRegla(c, r);
        }
    }

    private static void iniciarServidorParaRegla(Context c, Regla r) {
        int destinoPort = (r.puertoInterno == 22 ? 8022 : r.puertoInterno);
        if (r.puertoExterno == destinoPort) {
            Log.w(TAG, "Regla omitida para evitar bucle infinito: puerto externo (" + r.puertoExterno + ") coincide con destino");
            return;
        }
        // Puertos privilegiados (< 1024, ej. 80, 443, 22, 21) se delegan al proxy shell UID 2000
        if (r.puertoExterno < 1024) {
            Log.i(TAG, "Puerto privilegiado :" + r.puertoExterno + " delegado a proxy-ports en espacio shell UID 2000");
            activarPuertoEnShell(r.puertoExterno);
            return;
        }
        try {
            ServerSocket ss = new ServerSocket(r.puertoExterno, 50, InetAddress.getByName("0.0.0.0"));
            Thread t = new Thread(() -> bucleAceptar(c, r, ss), "pforward-" + r.puertoExterno);
            ServidorForward sf = new ServidorForward(r, ss, t);
            servidores.put(r.puertoExterno, sf);
            t.start();
            Log.i(TAG, "Port forward escuchando en :" + r.puertoExterno + " -> " + r.instanciaId + ":" + r.puertoInterno);
        } catch (IOException e) {
            Log.w(TAG, "No se pudo enlazar puerto externo " + r.puertoExterno + ": " + e.getMessage());
        }
    }

    private static void bucleAceptar(Context c, Regla r, ServerSocket ss) {
        while (!Thread.currentThread().isInterrupted() && !ss.isClosed()) {
            try {
                Socket cliente = ss.accept();
                if (poolPipes != null && !poolPipes.isShutdown()) {
                    poolPipes.execute(() -> procesarConexion(c, r, cliente));
                } else {
                    cliente.close();
                }
            } catch (IOException e) {
                if (ss.isClosed()) break;
                Log.w(TAG, "error en accept puerto " + r.puertoExterno + ": " + e.getMessage());
            }
        }
    }

    private static void procesarConexion(Context c, Regla r, Socket cliente) {
        int puertoDestino = (r.puertoInterno == 22 ? 8022 : r.puertoInterno);
        if (puertoDestino == r.puertoExterno) {
            Log.w(TAG, "Bucle evitado: puerto externo y destino son " + puertoDestino);
            try { cliente.close(); } catch (Exception ignored) { }
            return;
        }
        Socket destino = null;
        try {
            // Resolver IP de loopback virtual destino para la instancia
            String hostDestino = "127.0.0.1";
            if (r.instanciaId != null && !r.instanciaId.isEmpty()) {
                String ipVirt = ipParaInstancia(c, r.instanciaId);
                if (ipVirt.contains("/")) ipVirt = ipVirt.substring(0, ipVirt.indexOf('/'));
                String[] partes = ipVirt.trim().split("\\.");
                if (partes.length == 4) {
                    try {
                        int b2 = Integer.parseInt(partes[1]);
                        int b3 = Integer.parseInt(partes[2]);
                        int b4 = Integer.parseInt(partes[3]);
                        hostDestino = "127." + b2 + "." + b3 + "." + b4;
                    } catch (NumberFormatException ignorada) { }
                }
            }
            Log.i(TAG, "Conexión aceptada en :" + r.puertoExterno + ", reenviando a " + hostDestino + ":" + puertoDestino);
            destino = new Socket(hostDestino, puertoDestino);
            Socket finalDestino = destino;

            if (poolPipes != null && !poolPipes.isShutdown()) {
                poolPipes.execute(() -> reenviarFlujo(cliente, finalDestino));
                poolPipes.execute(() -> reenviarFlujo(finalDestino, cliente));
            } else {
                cliente.close();
                destino.close();
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

    public static boolean esProxy22Habilitado(Context c) {
        return c.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
                .getBoolean(PREF_PROXY22_HABILITADO, false);
    }

    public static void setProxy22Habilitado(Context c, boolean hab) {
        c.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(PREF_PROXY22_HABILITADO, hab)
                .apply();
        actualizarProxy22Target(c);
    }

    public static String obtenerProxy22Target(Context c) {
        String t = c.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
                .getString(PREF_PROXY22_TARGET, null);
        if (t == null || t.trim().isEmpty()) {
            SistemaLinux.Instancia sel = SistemaLinux.instanciaSeleccionada(c);
            if (sel != null) return sel.id;
            List<SistemaLinux.Instancia> list = SistemaLinux.listarInstancias(c);
            if (!list.isEmpty()) return list.get(0).id;
            return "arch-principal";
        }
        return t.trim();
    }

    public static void setProxy22Target(Context c, String target) {
        c.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
                .edit()
                .putString(PREF_PROXY22_TARGET, target.trim())
                .apply();
        actualizarProxy22Target(c);
    }

    public static void actualizarProxy22Target(Context c) {
        try {
            String target = obtenerProxy22Target(c);
            String hostDestino = "127.0.0.1";
            int puertoDestino = 8022;

            if (target.contains(":")) {
                String[] partes = target.split(":");
                hostDestino = partes[0].trim();
                try { puertoDestino = Integer.parseInt(partes[1].trim()); } catch (Exception ignored) { }
            } else {
                String ipVirt = ipParaInstancia(c, target);
                if (ipVirt.contains("/")) ipVirt = ipVirt.substring(0, ipVirt.indexOf('/'));
                String[] partes = ipVirt.trim().split("\\.");
                if (partes.length == 4) {
                    try {
                        int b2 = Integer.parseInt(partes[1]);
                        int b3 = Integer.parseInt(partes[2]);
                        int b4 = Integer.parseInt(partes[3]);
                        hostDestino = "127." + b2 + "." + b3 + "." + b4;
                    } catch (NumberFormatException ignorada) { }
                }
            }

            java.io.File tf = new java.io.File(ARCHIVO_TARGET_PROXY22);
            try (java.io.FileWriter fw = new java.io.FileWriter(tf, false)) {
                fw.write(hostDestino + ":" + puertoDestino + "\n");
            }
            tf.setReadable(true, false);
            tf.setWritable(true, false);
            Log.i(TAG, "Proxy SSH puerto 22 actualizado a destino " + hostDestino + ":" + puertoDestino);
        } catch (Exception e) {
            Log.w(TAG, "Error actualizando target de proxy 22: " + e.getMessage());
        }
    }

    public static void sincronizarProxyPortsConf(Context c) {
        try {
            List<Regla> reglas = listarReglas(c);
            StringBuilder sb = new StringBuilder();
            sb.append("# proxy-ports.conf - Reenvío universal de puertos en espacio shell\n");
            for (Regla r : reglas) {
                if (!r.activa) continue;
                int destinoPort = (r.puertoInterno == 22 ? 8022 : r.puertoInterno);
                String hostDestino = "127.0.0.1";
                if (r.instanciaId != null && !r.instanciaId.isEmpty()) {
                    String ipVirt = ipParaInstancia(c, r.instanciaId);
                    if (ipVirt.contains("/")) ipVirt = ipVirt.substring(0, ipVirt.indexOf('/'));
                    String[] partes = ipVirt.trim().split("\\.");
                    if (partes.length == 4) {
                        try {
                            int b2 = Integer.parseInt(partes[1]);
                            int b3 = Integer.parseInt(partes[2]);
                            int b4 = Integer.parseInt(partes[3]);
                            hostDestino = "127." + b2 + "." + b3 + "." + b4;
                        } catch (NumberFormatException ignorada) { }
                    }
                }
                sb.append(r.puertoExterno).append(" ").append(hostDestino).append(" ").append(destinoPort).append("\n");
            }
            java.io.File cf = new java.io.File(ARCHIVO_CONF_PROXY_PORTS);
            try (java.io.FileWriter fw = new java.io.FileWriter(cf, false)) {
                fw.write(sb.toString());
            }
            cf.setReadable(true, false);
            cf.setWritable(true, false);
            Log.i(TAG, "Sincronizado " + ARCHIVO_CONF_PROXY_PORTS + " con " + reglas.size() + " reglas");
        } catch (Exception e) {
            Log.w(TAG, "Error escribiendo proxy-ports.conf: " + e.getMessage());
        }
    }

    public static void activarPuertoEnShell(int puertoExterno) {
        // Si hay una conexión ADB activa o daemon de shell en ejecución, se asegura el listener
        new Thread(() -> {
            try {
                java.io.File daemon = new java.io.File("/data/local/tmp/proxy-ports-daemon");
                if (daemon.exists()) {
                    Runtime.getRuntime().exec(new String[]{"/system/bin/sh", daemon.getAbsolutePath(), "start", String.valueOf(puertoExterno)});
                }
            } catch (Exception ignored) { }
        }, "shell-port-starter").start();
    }

    public static boolean estaPuertoActivo(int puerto) {
        try (Socket s = new Socket()) {
            s.connect(new java.net.InetSocketAddress("127.0.0.1", puerto), 120);
            return true;
        } catch (Exception ignored) {
            return false;
        }
    }

    public static boolean estaProxy22Activo() {
        return estaPuertoActivo(22);
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
