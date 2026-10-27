package dev.ben4shot.glibcprueba;

import android.content.Context;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.List;

// capa.tgz al día (B23): apk/armar.sh deja su sha256 en el asset capa.sha256 e instalar.sh lo copia a
// var/lib/linux-android/capa.sha256 al extraer la capa. Si difieren, la instancia está atrasada.
final class Capa {
    private Capa() { }

    // hashApk vacío: el APK no trae instalador. hashInstancia vacío: instancia creada antes de B23.
    static boolean atrasada(String hashApk, String hashInstancia) {
        return !hashApk.isEmpty() && !hashApk.equals(hashInstancia);
    }

    // Atrasada: /system/bin/sh corre instalar.sh (MODO=actualizar), que termina con exec del comando de siempre.
    static String[] comando(boolean atrasada, String script, String[] siguiente) {
        if (!atrasada) return siguiente;
        String[] r = new String[4 + siguiente.length];
        r[0] = "/system/bin/sh";
        r[1] = "-c";
        r[2] = script;
        r[3] = "instalar.sh";
        System.arraycopy(siguiente, 0, r, 4, siguiente.length);
        return r;
    }

    // /system/bin/sh es bionic y no arranca con el LD_PRELOAD de la instancia (glibc): va aparte e instalar.sh lo
    // devuelve antes del exec.
    static void apartarPreload(List<String> env) {
        env.replaceAll(v -> v.startsWith("LD_PRELOAD=") ? "LINUX_" + v : v);
    }

    static boolean atrasada(Context c, File p) {
        String instancia;
        try (InputStream i = new FileInputStream(new File(p, "var/lib/linux-android/capa.sha256"))) {
            instancia = leer(i);
        } catch (IOException e) {
            instancia = "";
        }
        return atrasada(hashApk(c), instancia);
    }

    static String hashApk(Context c) {
        try (InputStream i = c.getAssets().open("capa.sha256")) {
            return leer(i);
        } catch (IOException e) {
            return "";
        }
    }

    private static String leer(InputStream i) throws IOException {
        ByteArrayOutputStream b = new ByteArrayOutputStream();
        i.transferTo(b);
        return b.toString(StandardCharsets.US_ASCII.name()).trim();
    }
}
