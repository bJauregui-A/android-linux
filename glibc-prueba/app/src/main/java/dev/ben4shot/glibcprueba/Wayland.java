package dev.ben4shot.glibcprueba;

import android.content.Context;
import android.os.Process;
import android.util.Log;
import android.view.Surface;

import java.io.File;

// Anfitrión Wayland (app/src/main/cpp/anfitrion.c): un solo socket para toda la app, files/wayland/wayland-0.
// Cada instancia lo ve por un enlace en <prefijo>/run/user/<uid> (XDG_RUNTIME_DIR=/run/user/<uid> dentro del prefijo),
// así borrar una instancia no se lleva el socket de las demás.
final class Wayland {
    static {
        System.loadLibrary("anfitrion");
    }

    // Ruta dentro del prefijo (la que ven los programas glibc).
    static String runtimeDir() {
        return "/run/user/" + Process.myUid();
    }

    private static boolean anfitrionIniciado;

    // Idempotente: lo llaman la terminal y WaylandActivity.
    static synchronized void iniciar(Context ctx) {
        iniciarPara(ctx, SistemaLinux.seleccionado(ctx));
    }

    static synchronized void iniciarPara(Context ctx, String instanciaId) {
        File carpetaApp = new File(ctx.getFilesDir(), "wayland");
        soloDelDueno(carpetaApp);
        if (!anfitrionIniciado) {
            anfitrionIniciado = iniciar(carpetaApp.getAbsolutePath());
            if (!anfitrionIniciado) Log.e("WAYLAND", "no arrancó el anfitrión en " + carpetaApp);
        }
        File raiz = instanciaId != null ? SistemaLinux.raiz(ctx, instanciaId) : SistemaLinux.raizSeleccionada(ctx);
        File dir = new File(raiz, runtimeDir().substring(1));
        soloDelDueno(dir);
        try {
            EnlacesWayland.enlazar(carpetaApp, dir);
        } catch (java.io.IOException e) {
            Log.w("WAYLAND", "enlace simbólico wayland-0", e);
        }
    }

    private static void soloDelDueno(File dir) {
        dir.mkdirs();
        dir.setReadable(false, false);
        dir.setWritable(false, false);
        dir.setExecutable(false, false);
        dir.setReadable(true, true);
        dir.setWritable(true, true);
        dir.setExecutable(true, true);
    }

    private static native boolean iniciar(String dir);

    private static String raizAlFrente;

    // El anfitrión muestra y da la entrada al escritorio de la instancia con esta raíz; los de las demás quedan de fondo.
    static synchronized void alFrente(String raiz) {
        raizAlFrente = raiz;
        alFrenteNativo(raiz);
    }

    static synchronized boolean estaAlFrente(String raiz) {
        return raiz.equals(raizAlFrente);
    }

    private static native void alFrenteNativo(String raiz);

    // surface null = la ventana se fue (el último cuadro queda guardado).
    static native void ventana(Surface surface, int ancho, int alto, int mmAncho, int mmAlto);

    // Limpia el fotograma retenido para no dejar residuos visuales al cambiar o cerrar sesión.
    static native void limpiarPantalla();

    // Puntero; coordenadas en píxeles de la vista.
    static native void mover(float x, float y);

    // Botón evdev (BTN_LEFT 0x110, BTN_RIGHT 0x111).
    static native void boton(int boton, boolean pulsado);

    // Scroll (unidades de rueda de Wayland); 0, 0 termina el gesto.
    static native void eje(float dx, float dy);

    // Deslizar con varios dedos (zwp_pointer_gestures_v1): fase 0 empieza,
    // 1 avanza (dx, dy en píxeles de la vista), 2 termina, 3 se cancela.
    static native void gesto(int fase, int dedos, float dx, float dy);

    // Código evdev (linux/input-event-codes.h).
    static native void tecla(int codigo, boolean pulsada);
}
