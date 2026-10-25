package dev.ben4shot.glibcprueba;

import android.content.Context;
import android.util.Log;

import java.io.File;
import java.io.FileWriter;
import java.util.List;

// Adaptador para Debian ARM64 (bookworm / trixie) sin root.
final class AdaptadorDebianArm64 implements AdaptadorInstalacion {
    private final String prefijo;
    private static final String TAG = "DEBIAN";

    public AdaptadorDebianArm64() {
        this("instancias/debian-principal");
    }

    public AdaptadorDebianArm64(String prefijo) {
        this.prefijo = prefijo != null && !prefijo.isEmpty() ? prefijo : "instancias/debian-principal";
    }

    @Override public String id() { return SistemaLinux.DEBIAN; }

    @Override public File raiz(Context contexto) {
        return new File(contexto.getFilesDir(), prefijo);
    }

    @Override public String cargador(Context contexto) {
        return contexto.getApplicationInfo().nativeLibraryDir + "/libldp.so";
    }

    @Override public String usuario(File raiz) {
        File f = new File(raiz, "var/lib/linux-android/usuario");
        try (java.io.BufferedReader r = new java.io.BufferedReader(new java.io.FileReader(f))) {
            String u = r.readLine();
            if (u != null && u.trim().matches("[a-z_][a-z0-9_-]*")) return u.trim();
        } catch (java.io.IOException ignorada) { }
        return "user";
    }

    @Override public String home(File raiz) { return "/home/" + usuario(raiz); }

    @Override public String shell(File raiz) {
        if (new File(raiz, "bin/bash").exists()) return "/bin/bash";
        if (new File(raiz, "usr/bin/bash").exists()) return "/usr/bin/bash";
        return "/bin/sh";
    }

    @Override public String supervisorSesion() { return "/usr/local/bin/sesion-android"; }

    @Override public String perfilesSesion() {
        return "/usr/local/share/linux-android/escritorios";
    }

    @Override public String estadoSesion() { return "/var/lib/linux-android"; }

    @Override public String perfilRescate() { return "openbox"; }

    @Override public String[] comandoTerminal(Context contexto) {
        return new String[]{"libldp.so", "/usr/bin/bash", "-l"};
    }

    @Override public boolean instalada(Context contexto) {
        File r = raiz(contexto);
        return new File(r, "var/lib/linux-android/instalado").exists();
    }

    @Override public boolean instaladorDisponible(Context contexto) {
        try (java.io.InputStream i = contexto.getAssets().open("base-debian.tgz")) {
            return true;
        } catch (java.io.IOException e) {
            return new File(contexto.getFilesDir(), "trabajo/base-debian.tar").exists()
                    || new File(contexto.getFilesDir(), "trabajo/base-debian.tgz").exists();
        }
    }

    @Override public String[] comandoInstalacion(Context contexto, List<String> entorno)
            throws java.io.IOException {
        return Instalador.comando(contexto, raiz(contexto), entorno);
    }

    @Override public void preparar(Context contexto, File raiz) {
        new File(raiz, "dev/shm").mkdirs();
        new File(raiz, "var/lib/linux-android").mkdirs();
        new File(raiz, "etc/apt/apt.conf.d").mkdirs();
        new File(raiz, "var/lib/dpkg").mkdirs();

        escribirSudo(raiz);
        escribirAptConf(raiz);
    }

    @Override public void agregarEntorno(Context contexto, File raiz, List<String> entorno) {
        String home = home(raiz);
        entorno.add("GLIBC_PREFIX=" + raiz);
        entorno.add("GLIBC_LOADER=" + cargador(contexto));
        entorno.add("HOME=" + home);
        entorno.add("USER=" + usuario(raiz));
        entorno.add("LOGNAME=" + usuario(raiz));
        entorno.add("SHELL=" + shell(raiz));
        entorno.add("PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin");
        entorno.add("LD_LIBRARY_PATH=/usr/lib/aarch64-linux-gnu:/lib/aarch64-linux-gnu:/usr/lib:/lib");
        entorno.add("LANG=C.UTF-8");
        entorno.add("TMPDIR=/tmp");
        entorno.add("DEBIAN_FRONTEND=noninteractive");
        entorno.add("LINUX_SESSION_PROFILES_DIR=" + perfilesSesion());
        entorno.add("LINUX_SESSION_STATE_DIR=" + estadoSesion());
        entorno.add("LINUX_SESSION_RECOVERY_PROFILE=" + perfilRescate());
    }

    private static void escribirSudo(File raiz) {
        // Con el sudo real puesto (marca del primer arranque) no hay wrapper: lo tapaba.
        if (new File(raiz, "etc/sudoers.d/10-linux-android").exists()) return;
        File f = new File(raiz, "usr/local/bin/sudo");
        f.getParentFile().mkdirs();
        try (FileWriter w = new FileWriter(f)) {
            w.write("#!/bin/bash\n"
                  + "# fakeroot de la glibc propia para Debian sin root\n"
                  + "export GLIBC_FAKEROOT=1\n"
                  + "while [ $# -gt 0 ]; do\n"
                  + "    case \"$1\" in\n"
                  + "        -E|--preserve-env|-s|-i)\n"
                  + "            shift ;;\n"
                  + "        -u)\n"
                  + "            shift 2 ;;\n"
                  + "        --)\n"
                  + "            shift; break ;;\n"
                  + "        *=*) \n"
                  + "            export \"$1\"; shift ;;\n"
                  + "        *)\n"
                  + "            break ;;\n"
                  + "    esac\n"
                  + "done\n"
                  + "exec \"$@\"\n");
            f.setExecutable(true, false);
        } catch (Exception e) {
            Log.e(TAG, "sudo", e);
        }
    }

    private static void escribirAptConf(File raiz) {
        File f = new File(raiz, "etc/apt/apt.conf.d/99android");
        if (f.exists()) return;
        f.getParentFile().mkdirs();
        try (FileWriter w = new FileWriter(f)) {
            w.write("// Configuración de APT para Android sin root\n"
                  + "APT::Sandbox::User \"root\";\n"
                  + "DPkg::Options {\"--force-not-root\"; \"--force-bad-path\";};\n");
        } catch (Exception e) {
            Log.e(TAG, "apt.conf", e);
        }
    }
}
