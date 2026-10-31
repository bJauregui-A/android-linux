package dev.ben4shot.glibcprueba;

import android.app.Application;
import android.system.Os;
import android.util.Log;

// Los procesos de una app arrancan con umask 077 (Android); en Linux es 022, y con 077 todo lo que crean los programas
// de la instancia nace 600/700 y los demás usuarios no lo pueden leer (B96). Corre en cada proceso de la app, y los
// hijos lo heredan.
public class Aplicacion extends Application {
    private static final int UMASK_LINUX = 022;

    @Override
    public void onCreate() {
        super.onCreate();
        try {
            Os.umask(UMASK_LINUX);
        } catch (RuntimeException e) {
            Log.w("Aplicacion", "no pude fijar el umask: " + e.getMessage());
        }
    }
}
