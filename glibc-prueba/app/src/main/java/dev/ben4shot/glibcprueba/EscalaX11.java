package dev.ben4shot.glibcprueba;

import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;

// DPI del servidor X: 96 x ANDROID_ESCALA, la misma escala que usa Wayland (2.5 en este teléfono; otro dispositivo la
// cambia en ~/.config/entorno-android de la instancia). El dpi físico de la pantalla (~400) dejaba MATE y GTK enormes.
final class EscalaX11 {
    private static final double POR_DEFECTO = 2.5;
    private static final int DPI_BASE = 96;

    private EscalaX11() { }

    static int dpi(File raiz, String home) {
        try {
            File f = new File(raiz, home + "/.config/entorno-android");
            return dpi(f.isFile() ? new String(Files.readAllBytes(f.toPath()), StandardCharsets.UTF_8) : null);
        } catch (java.io.IOException e) {
            return dpi(null);
        }
    }

    // contenido de entorno-android (null si no existe); la última ANDROID_ESCALA válida gana
    static int dpi(String contenido) {
        double escala = POR_DEFECTO;
        if (contenido != null) {
            for (String l : contenido.split("\n")) {
                l = l.trim();
                if (!l.startsWith("ANDROID_ESCALA=")) continue;
                try {
                    double v = Double.parseDouble(l.substring("ANDROID_ESCALA=".length()).trim());
                    if (v > 0) escala = v;
                } catch (NumberFormatException ignorada) { }
            }
        }
        return (int) Math.round(DPI_BASE * escala);
    }
}
