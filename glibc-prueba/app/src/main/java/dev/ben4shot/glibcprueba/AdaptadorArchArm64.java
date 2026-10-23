package dev.ben4shot.glibcprueba;

import android.content.Context;
import android.util.Log;

import java.io.File;
import java.io.FileWriter;
import java.util.List;

// Datos del rootfs Arch ARM64 actual. Mantiene su ABI/glibc, rutas de usuario y renderer.
// Permite prefijo relativo personalizado para soportar múltiples instancias de Arch.
final class AdaptadorArchArm64 implements AdaptadorInstalacion {
    private final String prefijo;
    private static final String TAG = "TERMINAL";

    public AdaptadorArchArm64() {
        this("instancias/arch-principal");
    }

    public AdaptadorArchArm64(String prefijo) {
        this.prefijo = prefijo != null && !prefijo.isEmpty() ? prefijo : "instancias/arch-principal";
    }

    @Override public String id() { return SistemaLinux.ARCH; }

    @Override public File raiz(Context contexto) {
        return new File(contexto.getFilesDir(), prefijo);
    }

    @Override public String cargador(Context contexto) {
        return contexto.getApplicationInfo().nativeLibraryDir + "/libldp.so";
    }

    @Override public String usuario(File raiz) {
        File f = new File(raiz, "var/lib/linux-android/usuario");
        if (!f.exists()) f = new File(raiz, "var/lib/arch-android/usuario");
        try (java.io.BufferedReader r = new java.io.BufferedReader(new java.io.FileReader(f))) {
            String u = r.readLine();
            if (u != null && u.trim().matches("[a-z_][a-z0-9_-]*")) return u.trim();
        } catch (java.io.IOException ignorada) { }
        return "user";
    }

    @Override public String home(File raiz) { return "/home/" + usuario(raiz); }

    @Override public String shell(File raiz) {
        return new File(raiz, "usr/bin/zsh").exists() ? "/usr/bin/zsh" : "/usr/bin/bash";
    }

    @Override public String supervisorSesion() { return "/usr/local/bin/sesion-android"; }

    @Override public String perfilesSesion() {
        File nuevo = new File("/usr/local/share/linux-android/escritorios");
        return "/usr/local/share/linux-android/escritorios";
    }

    @Override public String estadoSesion() { return "/var/lib/linux-android"; }

    @Override public String perfilRescate() { return "sway"; }

    @Override public String[] comandoTerminal(Context contexto) {
        return new String[]{"libldp.so", "/usr/bin/bash", "-l"};
    }

    @Override public boolean instalada(Context contexto) {
        return Instalador.instalada(raiz(contexto));
    }

    @Override public boolean instaladorDisponible(Context contexto) {
        return Instalador.disponible(contexto);
    }

    @Override public String[] comandoInstalacion(Context contexto, List<String> entorno)
            throws java.io.IOException {
        return Instalador.comando(contexto, raiz(contexto), entorno);
    }

    @Override public void preparar(Context contexto, File raiz) {
        new File(raiz, "dev/shm").mkdirs();
        File estadoNuevo = new File(raiz, "var/lib/linux-android");
        estadoNuevo.mkdirs();
        File estadoViejo = new File(raiz, "var/lib/arch-android");
        if (!estadoViejo.exists()) {
            try {
                android.system.Os.symlink("linux-android", estadoViejo.getAbsolutePath());
            } catch (Exception e) {
                estadoViejo.mkdirs();
            }
        }
        File shareNuevo = new File(raiz, "usr/local/share/linux-android");
        File shareViejo = new File(raiz, "usr/local/share/arch-android");
        if (shareViejo.exists() && !shareNuevo.exists()) {
            try {
                android.system.Os.symlink("arch-android", shareNuevo.getAbsolutePath());
            } catch (Exception ignorada) { }
        } else if (shareNuevo.exists() && !shareViejo.exists()) {
            try {
                android.system.Os.symlink("linux-android", shareViejo.getAbsolutePath());
            } catch (Exception ignorada) { }
        }
        escribirSudo(raiz);
    }

    @Override public void agregarEntorno(Context contexto, File raiz, List<String> entorno) {
        String home = home(raiz);
        entorno.add("GLIBC_PREFIX=" + raiz);
        entorno.add("GLIBC_LOADER=" + cargador(contexto));
        entorno.add("HOME=" + home);
        entorno.add("USER=" + usuario(raiz));
        entorno.add("LOGNAME=" + usuario(raiz));
        entorno.add("SHELL=" + shell(raiz));
        entorno.add("PATH=/usr/local/bin:/usr/bin");
        entorno.add("LANG=C.UTF-8");
        entorno.add("TMPDIR=/tmp");
        entorno.add("LINUX_SESSION_PROFILES_DIR=" + perfilesSesion());
        entorno.add("LINUX_SESSION_STATE_DIR=" + estadoSesion());
        entorno.add("LINUX_SESSION_RECOVERY_PROFILE=" + perfilRescate());

        // Entorno gráfico específico de Arch + Mesa Turnip y wlroots compilados para Android.
        entorno.add("VK_ICD_FILENAMES=" + propio(raiz, "turnip") + "/share/vulkan/icd.d/freedreno_icd.aarch64.json");
        entorno.add("MESA_LOADER_DRIVER_OVERRIDE=zink");
        entorno.add("GLYCIN_DISABLE_SANDBOX=i-know-the-risks");
        entorno.add("MOZ_SHM_NO_SEALS=1");
        entorno.add("SDL_JOYSTICK_DISABLE_UDEV=1");

        String wlroots = propio(raiz, "wlroots");
        if (new File(raiz, wlroots + "/lib/libwlroots-0.20.so").exists()) {
            entorno.add("WLR_RENDERER=vulkan");
            entorno.add("LD_LIBRARY_PATH=" + wlroots + "/lib");
        } else {
            entorno.add("WLR_RENDERER=pixman");
            entorno.add("MESA_VK_WSI_DEBUG=sw");
        }
        String eglZink = propio(raiz, "turnip") + "/lib/libegl-zink.so";
        if (new File(raiz, eglZink).exists()) entorno.add("LD_PRELOAD=" + eglZink);
        entornoPropio(new File(raiz, home + "/.config/entorno-android"), entorno);
    }

    private static String propio(File raiz, String nombre) {
        String local = "/usr/local/" + nombre;
        if (new File(raiz, local).isDirectory()) return local;
        return "/home/" + usuarioLocal(raiz) + "/" + nombre;
    }

    private static String usuarioLocal(File raiz) {
        File f = new File(raiz, "var/lib/linux-android/usuario");
        if (!f.exists()) f = new File(raiz, "var/lib/arch-android/usuario");
        try (java.io.BufferedReader r = new java.io.BufferedReader(new java.io.FileReader(f))) {
            String u = r.readLine();
            if (u != null && u.trim().matches("[a-z_][a-z0-9_-]*")) return u.trim();
        } catch (java.io.IOException ignorada) { }
        return "user";
    }

    private static void entornoPropio(File f, List<String> entorno) {
        if (!f.exists()) return;
        try (java.io.BufferedReader r = new java.io.BufferedReader(new java.io.FileReader(f))) {
            for (String l; (l = r.readLine()) != null; ) {
                l = l.trim();
                int i = l.indexOf('=');
                if (l.startsWith("#") || i <= 0) continue;
                String clave = l.substring(0, i + 1);
                entorno.removeIf(v -> v.startsWith(clave));
                entorno.add(l);
            }
        } catch (java.io.IOException e) {
            Log.e(TAG, "entorno-android", e);
        }
    }

    private static void escribirSudo(File raiz) {
        File f = new File(raiz, "usr/local/bin/sudo");
        if (f.exists()) return;
        f.getParentFile().mkdirs();
        try (FileWriter w = new FileWriter(f)) {
            w.write("#!/usr/bin/bash\n# fakeroot de la glibc propia, escrito por la app\nGLIBC_FAKEROOT=1 exec \"$@\"\n");
            f.setExecutable(true, false);
        } catch (Exception e) {
            Log.e(TAG, "sudo", e);
        }
    }
}
