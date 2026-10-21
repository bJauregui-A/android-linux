package dev.ben4shot.glibcprueba;

import android.content.ActivityNotFoundException;
import android.content.Context;
import android.content.Intent;
import android.net.LocalServerSocket;
import android.net.LocalSocket;
import android.net.LocalSocketAddress;
import android.net.Uri;
import android.os.Process;
import android.util.Log;

import java.io.BufferedReader;
import java.io.File;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;

// xdg-open → Android. android-abrir (android/ en el repo, /usr/local/bin en el prefijo) se
// conecta al socket /run/android-abrir.sock del prefijo y manda una línea: una URL o la ruta
// absoluta de un archivo (como la ve Linux). Aquí se abre con un intent ACTION_VIEW; los
// archivos van como content:// (Archivos.java), otras apps no pueden leer files/.
// Responde "ok" o "error: ..." y cierra.
class Abrir {
    private static final String TAG = "ABRIR";
    private static Context ctx;
    private static LocalServerSocket servidor;
    // dueño del descriptor del servidor (ver Mandos)
    private static LocalSocket enlazado;

    static synchronized void iniciar(Context c) {
        if (servidor != null) return;
        ctx = c.getApplicationContext();
        File socket = new File(SistemaLinux.raizSeleccionada(c), "run/android-abrir.sock");
        try {
            socket.getParentFile().mkdirs();
            socket.delete();
            enlazado = new LocalSocket(LocalSocket.SOCKET_STREAM);
            enlazado.bind(new LocalSocketAddress(socket.getPath(), LocalSocketAddress.Namespace.FILESYSTEM));
            servidor = new LocalServerSocket(enlazado.getFileDescriptor());
            new Thread(Abrir::aceptar, "abrir").start();
        } catch (Exception e) {
            Log.e(TAG, "socket", e);
        }
    }

    private static void aceptar() {
        while (true) {
            try (LocalSocket c = servidor.accept()) {
                if (c.getPeerCredentials().getUid() != Process.myUid()) continue;
                String linea = new BufferedReader(new InputStreamReader(c.getInputStream(),
                        StandardCharsets.UTF_8)).readLine();
                String r = linea == null ? "error: vacío" : abrir(linea.trim());
                OutputStream o = c.getOutputStream();
                o.write((r + "\n").getBytes(StandardCharsets.UTF_8));
                o.flush();
            } catch (Exception e) {
                Log.w(TAG, "cliente", e);
            }
        }
    }

    private static String abrir(String que) {
        Intent i = new Intent(Intent.ACTION_VIEW);
        if (que.startsWith("/") || que.startsWith("file://")) {
            String ruta = que.startsWith("/") ? que : Uri.parse(que).getPath();
            File f = Archivos.real(ctx, ruta);
            if (f == null || !f.isFile()) return "error: no existe " + ruta;
            i.setDataAndType(Archivos.uri(ctx, ruta), Archivos.tipo(f.getName()));
            i.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        } else {
            i.setData(Uri.parse(que));
        }
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        try {
            // Android solo deja abrir activities desde una app visible: vale mientras se
            // está en sway (WaylandActivity al frente).
            // Sin chooser: la app por defecto (Edge para links) o el diálogo de Android.
            ctx.startActivity(i);
            Log.i(TAG, que);
            return "ok";
        } catch (ActivityNotFoundException e) {
            return "error: ninguna app abre " + que;
        } catch (Exception e) {
            Log.w(TAG, que, e);
            return "error: " + e;
        }
    }
}
