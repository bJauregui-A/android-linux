package dev.ben4shot.glibcprueba;

import android.content.Context;
import android.content.SharedPreferences;

import java.io.File;
import java.util.Arrays;
import java.util.List;

// Registro del selector. Cada distribución tendrá un rootfs independiente; por ahora solo
// Arch usa el prefijo histórico "archlinux" y tiene instalador en el APK.
final class SistemaLinux {
    static final String ARCH = "arch-arm64";
    private static final AdaptadorInstalacion ADAPTADOR_ARCH = new AdaptadorArchArm64();

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

    static List<Opcion> opciones(Context c) {
        AdaptadorInstalacion arch = adaptador(ARCH);
        boolean instalado = arch.instalada(c);
        boolean instalable = arch.instaladorDisponible(c);
        String estadoArch = instalado ? "Instalado" : instalable ? "Listo para instalar" : "No instalado";
        return Arrays.asList(
                new Opcion(ARCH, "Arch Linux ARM", "ARM64", estadoArch, instalado || instalable),
                new Opcion("debian-arm64", "Debian", "arm64", "Aún no disponible", false),
                new Opcion("ubuntu-arm64", "Ubuntu", "arm64", "Aún no disponible", false));
    }

    static String seleccionado(Context c) {
        String id = preferencias(c).getString("sistema", ARCH);
        for (Opcion o : opciones(c))
            if (o.id.equals(id) && o.disponible) return id;
        return ARCH;
    }

    static void seleccionar(Context c, String id) {
        for (Opcion o : opciones(c)) {
            if (o.id.equals(id) && o.disponible) {
                preferencias(c).edit().putString("sistema", id).apply();
                return;
            }
        }
        throw new IllegalArgumentException("Sistema Linux no disponible: " + id);
    }

    static File raiz(Context c, String id) {
        return adaptador(id).raiz(c);
    }

    static File raizSeleccionada(Context c) {
        return adaptadorSeleccionado(c).raiz(c);
    }

    static AdaptadorInstalacion adaptador(String id) {
        if (ARCH.equals(id)) return ADAPTADOR_ARCH;
        throw new IllegalArgumentException("Sin adaptador registrado para " + id);
    }

    static AdaptadorInstalacion adaptadorSeleccionado(Context c) {
        return adaptador(seleccionado(c));
    }

    private static SharedPreferences preferencias(Context c) {
        return c.getSharedPreferences("instalacion-linux", Context.MODE_PRIVATE);
    }
}
