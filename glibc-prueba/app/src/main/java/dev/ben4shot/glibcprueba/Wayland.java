package dev.ben4shot.glibcprueba;

import android.content.Context;
import android.os.Process;
import android.util.Log;
import android.view.Surface;

import java.io.File;

// Anfitrión Wayland (app/src/main/cpp/anfitrion.c): socket wayland-0 en
// <prefijo>/run/user/<uid>, que dentro del prefijo es XDG_RUNTIME_DIR=/run/user/<uid>.
final class Wayland {
    static {
        System.loadLibrary("anfitrion");
    }

    // Ruta dentro del prefijo (la que ven los programas glibc).
    static String runtimeDir() {
        return "/run/user/" + Process.myUid();
    }

    // Idempotente: lo llaman la terminal y WaylandActivity.
    static synchronized void iniciar(Context ctx) {
        File dir = new File(new File(ctx.getFilesDir(), TerminalService.PREFIJO), runtimeDir().substring(1));
        dir.mkdirs();
        dir.setReadable(false, false);
        dir.setWritable(false, false);
        dir.setExecutable(false, false);
        dir.setReadable(true, true);
        dir.setWritable(true, true);
        dir.setExecutable(true, true);
        if (!iniciar(dir.getAbsolutePath())) Log.e("WAYLAND", "no arrancó el anfitrión en " + dir);
    }

    private static native boolean iniciar(String dir);

    // surface null = la ventana se fue (el último cuadro queda guardado).
    static native void ventana(Surface surface, int ancho, int alto, int mmAncho, int mmAlto);

    // Puntero; coordenadas en píxeles de la vista.
    static native void mover(float x, float y);

    // Botón evdev (BTN_LEFT 0x110, BTN_RIGHT 0x111).
    static native void boton(int boton, boolean pulsado);

    // Scroll (unidades de rueda de Wayland); 0, 0 termina el gesto.
    static native void eje(float dx, float dy);

    // Código evdev (linux/input-event-codes.h).
    static native void tecla(int codigo, boolean pulsada);
}
