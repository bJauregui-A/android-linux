package dev.ben4shot.glibcprueba;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.util.Log;

import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;

// Solo depuración (B29): corre un script de prueba dentro de una instancia, con el
// contexto real de la app. Se dispara desde adb con scripts/probar-en-telefono.sh.
// Un receptor dura ~10 s, así que solo valida y le pasa el pedido a TerminalService.
public class ReceptorPruebas extends BroadcastReceiver {
    private static final String TAG = "PRUEBAS";

    @Override
    public void onReceive(Context contexto, Intent intent) {
        String instancia = intent.getStringExtra("instancia");
        String script = intent.getStringExtra("script");
        String id = intent.getStringExtra("id");
        int limite = intent.getIntExtra("limite", 300);
        if (id == null || !id.matches("[a-z0-9-]+")) {
            Log.w(TAG, "id inválido: " + id);
            return;
        }
        Intent servicio = new Intent(contexto, TerminalService.class)
                .setAction(TerminalService.EJECUTAR_PRUEBA)
                .putExtra("instancia", instancia)
                .putExtra("script", script)
                .putExtra("id", id)
                .putExtra("limite", limite);
        try {
            contexto.startForegroundService(servicio);
        } catch (RuntimeException e) {
            // Android no deja iniciar el servicio desde segundo plano: se avisa a la PC.
            Log.w(TAG, "sin servicio: " + e.getMessage());
            File dir = new File(contexto.getFilesDir(), "pruebas/" + id);
            dir.mkdirs();
            try {
                Files.write(new File(dir, "estado").toPath(),
                        "error: sin servicio\n".getBytes(StandardCharsets.UTF_8));
                Files.write(new File(dir, "codigo").toPath(), "2\n".getBytes(StandardCharsets.UTF_8));
            } catch (IOException ignorada) { }
        }
    }
}
