package dev.ben4shot.glibcprueba;

import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.util.Base64;
import android.util.Log;

import java.io.BufferedReader;
import java.io.File;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;

// Portapapeles Android ↔ sesión Wayland. El backend wayland de wlroots no reenvía el portapapeles
// al anfitrión, así que el puente va por dentro del compositor con wl-clipboard (data-control):
//  Linux → Android: `wl-paste --watch` manda una línea base64 por cambio → setPrimaryClip.
//  Android → Linux: al ganar el foco (Android solo deja leer a la app enfocada) → wl-copy.
// `ultimo` evita que una copia rebote de un lado al otro.
class Portapapeles {
    private static final String TAG = "PORTAPAPELES";
    private static TerminalService servicio;
    private static Thread vigilante;
    private static volatile String ultimo;
    private static ClipboardManager.OnPrimaryClipChangedListener oyente;

    // Lo llama el servicio al arrancar el escritorio: vigila mientras viva (reintenta hasta
    // que su socket esté listo y si wl-paste se cae).
    static synchronized void iniciar(TerminalService s) {
        servicio = s;
        if (vigilante != null && vigilante.isAlive()) return;
        vigilante = new Thread(Portapapeles::vigilar, "portapapeles");
        vigilante.start();
    }

    private static void vigilar() {
        while (servicio.escritorioVivo()) {
            String protocolo = servicio.protocoloPantalla();
            if (protocolo == null) {
                try { Thread.sleep(500); } catch (InterruptedException e) { return; }
                continue;
            }
            if (!"wayland".equals(protocolo)) {
                try { Thread.sleep(1000); } catch (InterruptedException e) { return; }
                continue;
            }
            try {
                Process p = servicio.linux("/usr/bin/wl-paste", "--type", "text", "--watch",
                        "/usr/bin/sh", "-c", "base64 -w0; echo").start();
                BufferedReader r = new BufferedReader(new InputStreamReader(p.getInputStream()));
                for (String linea; (linea = r.readLine()) != null; ) haciaAndroid(linea);
                Log.i(TAG, "wl-paste terminó: " + p.waitFor());
            } catch (Exception e) {
                Log.e(TAG, "wl-paste", e);
            }
            try {
                Thread.sleep(2000);
            } catch (InterruptedException e) {
                return;
            }
        }
    }

    private static void haciaAndroid(String linea) {
        if (linea.isEmpty()) return; // portapapeles vacío o sin texto
        String texto;
        try {
            texto = new String(Base64.decode(linea, Base64.DEFAULT), StandardCharsets.UTF_8);
        } catch (IllegalArgumentException e) {
            return;
        }
        if (texto.equals(ultimo)) return;
        ultimo = texto;
        new Handler(Looper.getMainLooper()).post(() ->
                servicio.getSystemService(ClipboardManager.class)
                        .setPrimaryClip(ClipData.newPlainText("Linux", texto)));
    }

    // Lo llama WaylandActivity al ganar/perder el foco: mientras lo tiene, lo que se copie
    // en Android (ej. el portapapeles de Gboard) también pasa a la sesión Wayland.
    static void foco(Context ctx, boolean foco) {
        ClipboardManager cm = ctx.getSystemService(ClipboardManager.class);
        if (oyente != null) cm.removePrimaryClipChangedListener(oyente);
        oyente = null;
        if (!foco || servicio == null) return;
        oyente = () -> haciaLinux(ctx, cm);
        cm.addPrimaryClipChangedListener(oyente);
        haciaLinux(ctx, cm);
    }

    private static void haciaLinux(Context ctx, ClipboardManager cm) {
        ClipData clip = cm.getPrimaryClip();
        TerminalService s = servicio;
        if (clip == null || clip.getItemCount() == 0 || s == null || !s.escritorioVivo()
                || !"wayland".equals(s.protocoloPantalla())) return;
        CharSequence cs = clip.getItemAt(0).coerceToText(ctx);
        if (cs == null || cs.length() == 0) return;
        String texto = cs.toString();
        if (texto.equals(ultimo)) return;
        ultimo = texto;
        byte[] datos = texto.getBytes(StandardCharsets.UTF_8);
        new Thread(() -> {
            try {
                // Como argumento (por stdin desde Java llegaba vacío); un argumento no puede
                // pasar de 128 KiB (MAX_ARG_STRLEN), los textos más largos van por stdin.
                boolean corto = datos.length < 100_000;
                ProcessBuilder pb = corto ? s.linux("/usr/bin/wl-copy", "--", texto)
                        : s.linux("/usr/bin/wl-copy");
                pb.redirectErrorStream(true).redirectOutput(
                        new File(SistemaLinux.raizSeleccionada(s), "tmp/wl-copy.log"));
                Process p = pb.start();
                try (OutputStream o = p.getOutputStream()) {
                    if (!corto) o.write(datos);
                }
                Log.i(TAG, "wl-copy: " + datos.length + " bytes");
            } catch (Exception e) {
                Log.e(TAG, "wl-copy", e);
            }
        }, "wl-copy").start();
    }
}
