package dev.ben4shot.glibcprueba;

import android.content.Context;
import android.content.res.AssetFileDescriptor;
import android.util.Log;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.util.List;

// APK autoinstalable (apk/armar.sh): si falta el Arch, la terminal corre apk/instalar.sh, que
// extrae base.tgz y capa.tgz directo del APK (assets sin comprimir: offset y largo) y
// sigue con primer-arranque.sh dentro de Arch (pacman, juegos opcionales, ajustes).
final class Instalador {
    private static final String TAG = "INSTALADOR";

    private Instalador() { }

    // Instalado = lo marcó primer-arranque.sh, o un Arch de antes del instalador (con sway y
    // sin una instalación a medias).
    static boolean instalada(Context c) {
        File p = SistemaLinux.raiz(c, SistemaLinux.ARCH);
        File e = new File(p, "var/lib/arch-android");
        if (new File(e, "instalado").exists()) return true;
        return !new File(e, "instalando").exists() && new File(p, "usr/bin/sway").exists();
    }

    static boolean falta(Context c) {
        return !instalada(c);
    }

    // Este APK trae el instalador (los assets los arma apk/armar.sh; sin ellos, solo el cargador).
    static boolean disponible(Context c) {
        try (InputStream i = c.getAssets().open("instalar.sh")) {
            return true;
        } catch (IOException e) {
            return false;
        }
    }

    // Comando de la sesión de terminal: sh -c <instalar.sh>. Agrega a env lo que necesita.
    static String[] comando(Context c, List<String> env) throws IOException {
        env.add("APK=" + c.getApplicationInfo().sourceDir);
        ubicar(c, "base.tgz", "BASE", env);
        ubicar(c, "capa.tgz", "CAPA", env);
        env.add("ANDROID_DNS=" + String.join(" ", TerminalService.servidoresDns(c)));
        String script;
        try (InputStream i = c.getAssets().open("instalar.sh")) {
            ByteArrayOutputStream b = new ByteArrayOutputStream();
            i.transferTo(b);
            script = b.toString("UTF-8");
        }
        Log.i(TAG, "instalando en " + SistemaLinux.raiz(c, SistemaLinux.ARCH));
        return new String[]{"sh", "-c", script, "instalar.sh"};
    }

    private static void ubicar(Context c, String asset, String var, List<String> env) throws IOException {
        try (AssetFileDescriptor fd = c.getAssets().openFd(asset)) {
            env.add(var + "_OFF=" + fd.getStartOffset());
            env.add(var + "_LEN=" + fd.getLength());
        }
    }
}
