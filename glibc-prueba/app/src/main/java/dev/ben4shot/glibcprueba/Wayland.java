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

    private static File dirAnfitrion;

    // Idempotente: lo llaman la terminal y WaylandActivity.
    static synchronized void iniciar(Context ctx) {
        File dir = new File(SistemaLinux.raizSeleccionada(ctx), runtimeDir().substring(1));
        dir.mkdirs();
        dir.setReadable(false, false);
        dir.setWritable(false, false);
        dir.setExecutable(false, false);
        dir.setReadable(true, true);
        dir.setWritable(true, true);
        dir.setExecutable(true, true);
        if (dirAnfitrion == null) {
            if (iniciar(dir.getAbsolutePath())) {
                dirAnfitrion = dir;
            } else {
                Log.e("WAYLAND", "no arrancó el anfitrión en " + dir);
            }
        }
        // Si el anfitrión ya arrancó en otra instancia, enlazar el socket wayland-0
        if (dirAnfitrion != null && !dirAnfitrion.equals(dir)) {
            File srcSock = new File(dirAnfitrion, "wayland-0");
            File dstSock = new File(dir, "wayland-0");
            File srcLock = new File(dirAnfitrion, "wayland-0.lock");
            File dstLock = new File(dir, "wayland-0.lock");
            try {
                if (srcSock.exists() && (!dstSock.exists() || !dstSock.getCanonicalPath().equals(srcSock.getCanonicalPath()))) {
                    dstSock.delete();
                    android.system.Os.symlink(srcSock.getAbsolutePath(), dstSock.getAbsolutePath());
                }
                if (srcLock.exists() && (!dstLock.exists() || !dstLock.getCanonicalPath().equals(srcLock.getCanonicalPath()))) {
                    dstLock.delete();
                    android.system.Os.symlink(srcLock.getAbsolutePath(), dstLock.getAbsolutePath());
                }
            } catch (Exception e) {
                Log.w("WAYLAND", "enlace simbólico wayland-0", e);
            }
        }
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

    // Deslizar con varios dedos (zwp_pointer_gestures_v1): fase 0 empieza,
    // 1 avanza (dx, dy en píxeles de la vista), 2 termina, 3 se cancela.
    static native void gesto(int fase, int dedos, float dx, float dy);

    // Código evdev (linux/input-event-codes.h).
    static native void tecla(int codigo, boolean pulsada);
}
