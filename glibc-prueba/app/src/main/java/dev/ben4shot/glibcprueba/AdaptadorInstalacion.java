package dev.ben4shot.glibcprueba;

import android.content.Context;

import java.io.File;
import java.io.IOException;
import java.util.List;

// Responsabilidades que dependen del rootfs elegido, separadas del ciclo de vida Android.
// Cada instalación debe tener su propio adaptador antes de aparecer como disponible.
interface AdaptadorInstalacion {
    String id();
    File raiz(Context contexto);
    String cargador(Context contexto);
    String usuario(File raiz);
    String home(File raiz);
    String shell(File raiz);
    String supervisorSesion();
    String perfilesSesion();
    String estadoSesion();
    String perfilRescate();
    String[] comandoTerminal(Context contexto);
    boolean instalada(Context contexto);
    boolean instaladorDisponible(Context contexto);
    String[] comandoInstalacion(Context contexto, List<String> entorno) throws IOException;
    void preparar(Context contexto, File raiz);
    void agregarEntorno(Context contexto, File raiz, List<String> entorno);
}
