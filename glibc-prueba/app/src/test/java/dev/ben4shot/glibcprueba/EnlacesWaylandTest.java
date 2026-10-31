package dev.ben4shot.glibcprueba;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import java.io.File;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.Rule;
import org.junit.Test;
import org.junit.rules.TemporaryFolder;

public class EnlacesWaylandTest {
    @Rule public TemporaryFolder tmp = new TemporaryFolder();

    private static void assertEnlaza(File dirInstancia, String nombre, File carpetaApp) throws Exception {
        Path enlace = new File(dirInstancia, nombre).toPath();
        assertTrue(nombre + " no es un enlace", Files.isSymbolicLink(enlace));
        assertEquals(new File(carpetaApp, nombre).toPath(), Files.readSymbolicLink(enlace));
    }

    @Test
    public void enCarpetaVaciaCreaLosEnlacesAunqueElDestinoNoExista() throws Exception {
        File carpetaApp = tmp.newFolder("wayland");
        File dirInstancia = tmp.newFolder("instancia");

        EnlacesWayland.enlazar(carpetaApp, dirInstancia);

        assertEnlaza(dirInstancia, "wayland-0", carpetaApp);
        assertEnlaza(dirInstancia, "wayland-0.lock", carpetaApp);
    }

    @Test
    public void reemplazaElSocketViejoDeArchivosReales() throws Exception {
        File carpetaApp = tmp.newFolder("wayland");
        File dirInstancia = tmp.newFolder("instancia");
        assertTrue(new File(dirInstancia, "wayland-0").createNewFile());
        assertTrue(new File(dirInstancia, "wayland-0.lock").createNewFile());

        EnlacesWayland.enlazar(carpetaApp, dirInstancia);

        assertEnlaza(dirInstancia, "wayland-0", carpetaApp);
        assertEnlaza(dirInstancia, "wayland-0.lock", carpetaApp);
    }

    @Test
    public void reemplazaEnlacesAUnaInstanciaQueYaNoExiste() throws Exception {
        File carpetaApp = tmp.newFolder("wayland");
        File dirInstancia = tmp.newFolder("instancia");
        File borrada = new File(tmp.getRoot(), "borrada/run/user/1000");
        Files.createSymbolicLink(new File(dirInstancia, "wayland-0").toPath(), new File(borrada, "wayland-0").toPath());
        Files.createSymbolicLink(new File(dirInstancia, "wayland-0.lock").toPath(), new File(borrada, "wayland-0.lock").toPath());

        EnlacesWayland.enlazar(carpetaApp, dirInstancia);

        assertEnlaza(dirInstancia, "wayland-0", carpetaApp);
        assertEnlaza(dirInstancia, "wayland-0.lock", carpetaApp);
    }

    @Test
    public void noTocaLosEnlacesQueYaSonCorrectos() throws Exception {
        File carpetaApp = tmp.newFolder("wayland");
        File dirInstancia = tmp.newFolder("instancia");
        EnlacesWayland.enlazar(carpetaApp, dirInstancia);
        // Sin escritura, borrarlos o rehacerlos daría AccessDeniedException.
        assertTrue(dirInstancia.setWritable(false));
        try {
            EnlacesWayland.enlazar(carpetaApp, dirInstancia);
        } finally {
            dirInstancia.setWritable(true);
        }

        assertEnlaza(dirInstancia, "wayland-0", carpetaApp);
        assertEnlaza(dirInstancia, "wayland-0.lock", carpetaApp);
    }
}
