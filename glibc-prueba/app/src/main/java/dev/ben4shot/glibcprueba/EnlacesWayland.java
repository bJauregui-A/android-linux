package dev.ben4shot.glibcprueba;

import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;

/** Enlaces del socket Wayland de la app dentro del runtime dir de cada instancia; lógica pura, sin Context. */
final class EnlacesWayland {
    private static final String[] NOMBRES = {"wayland-0", "wayland-0.lock"};

    private EnlacesWayland() {}

    /**
     * Deja en {@code dirInstancia} un enlace a {@code carpetaApp/<nombre>} por cada archivo del socket.
     * Reemplaza archivos reales y enlaces a otro lado (rotos o no); los que ya son correctos no se tocan.
     */
    static void enlazar(File carpetaApp, File dirInstancia) throws IOException {
        for (String nombre : NOMBRES) {
            Path enlace = new File(dirInstancia, nombre).toPath();
            Path destino = new File(carpetaApp, nombre).toPath();
            if (Files.isSymbolicLink(enlace) && Files.readSymbolicLink(enlace).equals(destino)) continue;
            Files.deleteIfExists(enlace);
            Files.createSymbolicLink(enlace, destino);
        }
    }
    

}
