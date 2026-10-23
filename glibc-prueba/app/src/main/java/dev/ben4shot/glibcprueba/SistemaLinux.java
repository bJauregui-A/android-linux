package dev.ben4shot.glibcprueba;

import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

// Registro y gestor de instancias/entornos Linux. Cada instancia tiene su propio rootfs
// independiente y puede coexistir con otras del mismo sistema (ej: varios Arch Linux).
final class SistemaLinux {
    private static final String TAG = "SISTEMA";
    static final String ARCH = "arch-arm64";
    static final String DEBIAN = "debian-arm64";
    static final String UBUNTU = "ubuntu-arm64";

    private static final String PREF_INSTANCIAS = "instancias_json";
    private static final String PREF_ACTIVA = "instancia_activa";
    private static final String PREF_SISTEMA = "sistema";

    static final class DistroInfo {
        final String id;
        final String nombre;
        final String arquitectura;
        final boolean disponible;

        DistroInfo(String id, String nombre, String arquitectura, boolean disponible) {
            this.id = id;
            this.nombre = nombre;
            this.arquitectura = arquitectura;
            this.disponible = disponible;
        }
    }

    static final class Instancia {
        final String id;
        final String nombre;
        final String distroId;
        final String rutaRelativa;
        final long fechaCreacion;

        Instancia(String id, String nombre, String distroId, String rutaRelativa, long fechaCreacion) {
            this.id = id;
            this.nombre = nombre;
            this.distroId = distroId;
            this.rutaRelativa = rutaRelativa;
            this.fechaCreacion = fechaCreacion;
        }

        JSONObject aJson() throws JSONException {
            JSONObject obj = new JSONObject();
            obj.put("id", id);
            obj.put("nombre", nombre);
            obj.put("distroId", distroId);
            obj.put("rutaRelativa", rutaRelativa);
            obj.put("fechaCreacion", fechaCreacion);
            return obj;
        }

        static Instancia deJson(JSONObject obj) {
            return new Instancia(
                    obj.optString("id", "archlinux"),
                    obj.optString("nombre", "Arch Linux"),
                    obj.optString("distroId", ARCH),
                    obj.optString("rutaRelativa", "archlinux"),
                    obj.optLong("fechaCreacion", System.currentTimeMillis()));
        }
    }

    // Para compatibilidad con pantallas antiguas o llamadas directas
    static final class Opcion {
        final String id;
        final String nombre;
        final String arquitectura;
        final String estado;
        final boolean disponible;

        Opcion(String id, String nombre, String arquitectura, String estado, boolean disponible) {
            this.id = id;
            this.nombre = nombre;
            this.arquitectura = arquitectura;
            this.estado = estado;
            this.disponible = disponible;
        }
    }

    private SistemaLinux() { }

    static List<DistroInfo> distrosDisponibles() {
        return Arrays.asList(
                new DistroInfo(ARCH, "Arch Linux ARM", "ARM64", true),
                new DistroInfo(DEBIAN, "Debian", "arm64", false),
                new DistroInfo(UBUNTU, "Ubuntu", "arm64", false));
    }

    static synchronized List<Instancia> listarInstancias(Context c) {
        SharedPreferences p = preferencias(c);
        String raw = p.getString(PREF_INSTANCIAS, null);
        List<Instancia> lista = new ArrayList<>();
        if (raw != null) {
            if (!raw.trim().isEmpty()) {
                try {
                    JSONArray arr = new JSONArray(raw);
                    for (int i = 0; i < arr.length(); i++) {
                        lista.add(Instancia.deJson(arr.getJSONObject(i)));
                    }
                } catch (JSONException e) {
                    Log.e(TAG, "error leyendo instancias json", e);
                }
            }
            return lista;
        }
        // Primera ejecución limpia
        Instancia principal = new Instancia("arch-principal", "Arch Linux (Principal)",
                ARCH, "instancias/arch-principal", System.currentTimeMillis());
        lista.add(principal);
        guardarInstancias(c, lista);
        p.edit().putString(PREF_ACTIVA, principal.id).apply();
        return lista;
    }

    static synchronized void guardarInstancias(Context c, List<Instancia> lista) {
        JSONArray arr = new JSONArray();
        for (Instancia inst : lista) {
            try {
                arr.put(inst.aJson());
            } catch (JSONException ignorada) { }
        }
        preferencias(c).edit().putString(PREF_INSTANCIAS, arr.toString()).apply();
    }

    static synchronized Instancia instancia(Context c, String id) {
        for (Instancia i : listarInstancias(c)) {
            if (i.id.equals(id)) return i;
        }
        return null;
    }

    static synchronized Instancia instanciaSeleccionada(Context c) {
        List<Instancia> lista = listarInstancias(c);
        if (lista.isEmpty()) return null;
        String idActivo = preferencias(c).getString(PREF_ACTIVA, null);
        if (idActivo != null) {
            for (Instancia i : lista) {
                if (i.id.equals(idActivo)) return i;
            }
        }
        Instancia primera = lista.get(0);
        preferencias(c).edit().putString(PREF_ACTIVA, primera.id).apply();
        return primera;
    }

    static synchronized void seleccionarInstancia(Context c, String id) {
        for (Instancia i : listarInstancias(c)) {
            if (i.id.equals(id)) {
                preferencias(c).edit()
                        .putString(PREF_ACTIVA, id)
                        .putString(PREF_SISTEMA, i.distroId)
                        .apply();
                return;
            }
        }
        throw new IllegalArgumentException("Instancia no encontrada: " + id);
    }

    static synchronized Instancia crearInstancia(Context c, String nombre, String distroId) {
        if (!ARCH.equals(distroId)) {
            throw new IllegalArgumentException("La distribución " + distroId + " aún no está disponible");
        }
        List<Instancia> lista = listarInstancias(c);
        String slug = nombre.toLowerCase().replaceAll("[^a-z0-9_-]", "-").replaceAll("-+", "-");
        if (slug.isEmpty()) slug = "entorno";
        String id = slug + "-" + (System.currentTimeMillis() % 100000);
        String rutaRelativa = "instancias/" + id;
        File dir = new File(c.getFilesDir(), rutaRelativa);
        dir.mkdirs();

        Instancia nueva = new Instancia(id, nombre, distroId, rutaRelativa, System.currentTimeMillis());
        lista.add(nueva);
        guardarInstancias(c, lista);
        try {
            String ipSugerida = RedManager.ipParaInstancia(c, nueva.id);
            RedManager.asignarIp(c, nueva.id, "sub_default", ipSugerida);
        } catch (Exception ignorada) { }
        seleccionarInstancia(c, nueva.id);
        Log.i(TAG, "creada instancia " + id + " en " + rutaRelativa);
        return nueva;
    }

    static synchronized boolean eliminarInstancia(Context c, String id) {
        List<Instancia> lista = listarInstancias(c);
        Instancia objetivo = null;
        for (Instancia i : lista) {
            if (i.id.equals(id)) {
                objetivo = i;
                break;
            }
        }
        if (objetivo == null) return false;
        // Si la instancia eliminada está activa en TerminalService, cerrar sus procesos
        if (TerminalService.estaCorriendo(id)) {
            try {
                c.startService(new Intent(c, TerminalService.class)
                        .setAction(TerminalService.CERRAR_INSTANCIA)
                        .putExtra(TerminalService.EXTRA_INSTANCIA_ID, id));
            } catch (Exception e) {
                Log.w(TAG, "error al solicitar cierre de sesión", e);
            }
        }
        // Eliminar archivos del entorno en segundo plano para no bloquear el hilo de interfaz (evita ANR)
        File dir = new File(c.getFilesDir(), objetivo.rutaRelativa);
        new Thread(() -> {
            try {
                borrarRecursivo(dir);
                if (dir.exists()) {
                    String[] cmd = new String[]{"/system/bin/sh", "-c", "chmod -R u+w '" + dir.getAbsolutePath() + "' 2>/dev/null; rm -rf '" + dir.getAbsolutePath() + "'"};
                    Runtime.getRuntime().exec(cmd).waitFor();
                }
            } catch (Exception e) {
                Log.w(TAG, "error al borrar directorio de instancia", e);
            }
        }, "borrar-instancia").start();
        lista.remove(objetivo);
        guardarInstancias(c, lista);
        if (id.equals(preferencias(c).getString(PREF_ACTIVA, ""))) {
            if (!lista.isEmpty()) {
                seleccionarInstancia(c, lista.get(0).id);
            } else {
                preferencias(c).edit().remove(PREF_ACTIVA).remove(PREF_SISTEMA).apply();
            }
        }
        return true;
    }

    private static void borrarRecursivo(File f) {
        if (f == null || !f.exists()) return;
        f.setReadable(true, false);
        f.setWritable(true, false);
        f.setExecutable(true, false);
        if (f.isDirectory()) {
            File[] hijos = f.listFiles();
            if (hijos != null) {
                for (File h : hijos) borrarRecursivo(h);
            }
        }
        f.delete();
    }

    // Métodos de compatibilidad con el resto de la app
    static List<Opcion> opciones(Context c) {
        List<Instancia> instancias = listarInstancias(c);
        List<Opcion> res = new ArrayList<>();
        for (Instancia inst : instancias) {
            AdaptadorInstalacion adp = adaptador(c, inst);
            boolean instalado = adp.instalada(c);
            boolean instalable = adp.instaladorDisponible(c);
            String estado = instalado ? "Instalado" : instalable ? "Listo para instalar" : "No instalado";
            res.add(new Opcion(inst.id, inst.nombre, "ARM64 (" + inst.distroId + ")", estado, true));
        }
        // Distros plantilla no disponibles
        res.add(new Opcion(DEBIAN, "Debian", "arm64", "Aún no disponible", false));
        res.add(new Opcion(UBUNTU, "Ubuntu", "arm64", "Aún no disponible", false));
        return res;
    }

    static String seleccionado(Context c) {
        Instancia inst = instanciaSeleccionada(c);
        return inst != null ? inst.id : "arch-principal";
    }

    static void seleccionar(Context c, String id) {
        seleccionarInstancia(c, id);
    }

    static File raiz(Context c, String id) {
        if (id == null || id.isEmpty()) return adaptadorSeleccionado(c).raiz(c);
        Instancia inst = instancia(c, id);
        if (inst != null) return new File(c.getFilesDir(), inst.rutaRelativa);
        String ruta = id.startsWith("instancias/") ? id : "instancias/" + id;
        return new File(c.getFilesDir(), ruta);
    }

    static File raizSeleccionada(Context c) {
        return adaptadorSeleccionado(c).raiz(c);
    }

    static File estadoSesion(Context c, String id) {
        File r = raiz(c, id);
        File nuevo = new File(r, "var/lib/linux-android");
        if (nuevo.exists()) return nuevo;
        File antiguo = new File(r, "var/lib/arch-android");
        if (antiguo.exists()) return antiguo;
        return nuevo;
    }

    static File archivoEscritorio(Context c, String id) {
        File r = raiz(c, id);
        File fNuevo = new File(r, "var/lib/linux-android/escritorio");
        if (fNuevo.exists()) return fNuevo;
        File fAntiguo = new File(r, "var/lib/arch-android/escritorio");
        if (fAntiguo.exists()) return fAntiguo;
        return fNuevo;
    }

    static String leerEscritorio(Context c, String id) {
        File f = archivoEscritorio(c, id);
        if (f.isFile()) {
            try (java.io.BufferedReader br = new java.io.BufferedReader(new java.io.FileReader(f))) {
                String linea = br.readLine();
                if (linea != null && !linea.trim().isEmpty()) return linea.trim();
            } catch (Exception ignorada) { }
        }
        return "sway";
    }

    static void escribirEscritorio(Context c, String id, String escritorio) {
        File r = raiz(c, id);
        File dirNuevo = new File(r, "var/lib/linux-android");
        dirNuevo.mkdirs();
        File fNuevo = new File(dirNuevo, "escritorio");
        try (java.io.FileWriter fw = new java.io.FileWriter(fNuevo)) {
            fw.write(escritorio + "\n");
        } catch (Exception e) {
            Log.e(TAG, "error escribiendo escritorio", e);
        }

        // Compatibilidad: mantener sincronizado con var/lib/arch-android/escritorio
        File dirViejo = new File(r, "var/lib/arch-android");
        if (!dirViejo.exists()) {
            try {
                android.system.Os.symlink("linux-android", dirViejo.getAbsolutePath());
                return;
            } catch (Exception ignorada) {
                dirViejo.mkdirs();
            }
        }
        if (dirViejo.isDirectory() && !java.nio.file.Files.isSymbolicLink(dirViejo.toPath())) {
            try (java.io.FileWriter fw = new java.io.FileWriter(new File(dirViejo, "escritorio"))) {
                fw.write(escritorio + "\n");
            } catch (Exception ignorada) { }
        }
    }

    static AdaptadorInstalacion adaptador(Instancia inst) {
        if (inst == null || ARCH.equals(inst.distroId)) {
            return new AdaptadorArchArm64(inst != null ? inst.rutaRelativa : "instancias/arch-principal");
        }
        return new AdaptadorArchArm64(inst.rutaRelativa);
    }

    static AdaptadorInstalacion adaptador(Context c, Instancia inst) {
        return adaptador(inst);
    }

    static AdaptadorInstalacion adaptador(Context c, String id) {
        if (id == null || id.isEmpty()) return adaptadorSeleccionado(c);
        Instancia inst = instancia(c, id);
        if (inst != null) return adaptador(inst);
        if (ARCH.equals(id)) return adaptadorSeleccionado(c);
        String ruta = id.startsWith("instancias/") ? id : "instancias/" + id;
        return new AdaptadorArchArm64(ruta);
    }

    static AdaptadorInstalacion adaptador(String id) {
        if (id == null || id.isEmpty() || ARCH.equals(id)) return new AdaptadorArchArm64();
        String ruta = id.startsWith("instancias/") ? id : "instancias/" + id;
        return new AdaptadorArchArm64(ruta);
    }

    static AdaptadorInstalacion adaptadorSeleccionado(Context c) {
        Instancia inst = instanciaSeleccionada(c);
        if (inst == null) return new AdaptadorArchArm64();
        return adaptador(inst);
    }

    private static SharedPreferences preferencias(Context c) {
        return c.getSharedPreferences("instalacion-linux", Context.MODE_PRIVATE);
    }
}
