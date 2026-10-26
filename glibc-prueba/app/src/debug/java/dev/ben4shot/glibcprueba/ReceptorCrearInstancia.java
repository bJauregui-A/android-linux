package dev.ben4shot.glibcprueba;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.util.Log;

import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;

// Solo depuración (B11): crea una instancia e inicia su instalación sin abrir ninguna pantalla, para probar
// escritorios desde el PC (scripts/crear-en-telefono.sh). Deja escritas las respuestas que el asistente ya sabe
// saltar: $E/usuario, $E/hostname, $E/hash, $E/escritorio y $E/opcionales.
// Recibe el hash de la contraseña (openssl passwd -6), no la contraseña: no pasa en claro por adb.
// Devuelve el id de la instancia como resultado del broadcast (data="...").
public class ReceptorCrearInstancia extends BroadcastReceiver {
    private static final String TAG = "CREAR";

    @Override
    public void onReceive(Context c, Intent intent) {
        String eliminar = intent.getStringExtra("eliminar");     // id de una instancia de prueba que sobra
        if (eliminar != null) {
            setResultData(eliminar.matches("[A-Za-z0-9_-]+") && SistemaLinux.eliminarInstancia(c, eliminar)
                    ? "eliminada" : "error: no se eliminó");
            return;
        }
        String distro = intent.getStringExtra("distro");
        String nombre = intent.getStringExtra("nombre");
        String escritorio = intent.getStringExtra("escritorio");
        String opcionales = intent.getStringExtra("opcionales");   // ids separados por comas, puede faltar
        String usuario = intent.getStringExtra("usuario");
        String hash = intent.getStringExtra("hash");
        if (usuario == null) usuario = "user";
        if (nombre == null || escritorio == null || hash == null
                || !usuario.matches("[a-z_][a-z0-9_-]{0,31}") || !escritorio.matches("[a-z0-9-]+")
                || !nombre.matches("[A-Za-z0-9 _-]+") || !hash.matches("\\$6\\$[A-Za-z0-9./$]+")
                || (opcionales != null && !opcionales.matches("[a-z0-9,-]*"))) {
            Log.w(TAG, "pedido inválido");
            setResultData("error: pedido inválido");
            return;
        }
        String distroId = "debian".equals(distro) ? SistemaLinux.DEBIAN : "arch".equals(distro) ? SistemaLinux.ARCH : null;
        if (distroId == null) {
            setResultData("error: distro");
            return;
        }
        try {
            SistemaLinux.Instancia nueva = SistemaLinux.crearInstancia(c, nombre, distroId);
            File raiz = SistemaLinux.raiz(c, nueva.id);
            File estado = new File(raiz, "var/lib/linux-android");
            estado.mkdirs();
            escribir(new File(estado, "usuario"), usuario + "\n");
            SistemaLinux.escribirEscritorio(c, nueva.id, escritorio);
            StringBuilder ops = new StringBuilder();
            if (opcionales != null) for (String o : opcionales.split(",")) if (!o.isEmpty()) ops.append(o).append('\n');
            escribir(new File(estado, "opcionales"), ops.toString());
            // Nunca en /etc: la base se extrae después y lo pisaría. primer-arranque.sh los pasa a /etc.
            escribir(new File(estado, "hostname"), nueva.id.replaceAll("[^a-zA-Z0-9-]", "-") + "\n");
            File hashArchivo = new File(estado, "hash");
            escribir(hashArchivo, hash + "\n");
            hashArchivo.setReadable(false, false);
            hashArchivo.setReadable(true, true);
            c.startForegroundService(new Intent(c, TerminalService.class)
                    .setAction(TerminalService.INSTALAR_SIN_PANTALLA)
                    .putExtra(TerminalService.EXTRA_INSTANCIA_ID, nueva.id));
            setResultData(nueva.id);
        } catch (Exception e) {
            Log.e(TAG, "no se creó la instancia", e);
            setResultData("error: " + e.getMessage());
        }
    }

    private static void escribir(File f, String texto) throws java.io.IOException {
        Files.write(f.toPath(), texto.getBytes(StandardCharsets.UTF_8));
    }
}
