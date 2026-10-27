package dev.ben4shot.glibcprueba;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.util.DisplayMetrics;
import android.view.Surface;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;

// Lo que la vista (WaylandActivity) le manda al servidor gráfico: pantalla, ratón, tacto y teclado.
// Según el escritorio de la instancia va al anfitrión Wayland o a ServicioX11; la vista no sabe cuál.
final class Pantalla {
    private static volatile Activity vista;
    private static volatile String instancia;
    private static volatile boolean x11;
    // Qué instancias son X11: la superficie de una vista que se va llega después de que la nueva ya se abrió.
    private static final java.util.Map<String, Boolean> esX11Por = new java.util.concurrent.ConcurrentHashMap<>();

    private Pantalla() { }

    // La vista lo llama al abrirse, con la instancia que muestra.
    static void usar(Activity activity, String instanciaId) {
        vista = activity;
        instancia = instanciaId;
        x11 = esX11(activity, instanciaId);
        esX11Por.put(instanciaId, x11);
        if (x11) iniciarX11(activity, instanciaId);
    }

    // PROVEEDOR_PANTALLA=x11-directo en el escritorio.conf que la capa deja en la instancia.
    static boolean esX11(Context c, String instanciaId) {
        String escritorio = SistemaLinux.leerEscritorio(c, instanciaId);
        File conf = new File(SistemaLinux.raiz(c, instanciaId),
                "usr/local/share/arch-android/escritorios/" + escritorio + "/escritorio.conf");
        try (BufferedReader br = new BufferedReader(new FileReader(conf))) {
            for (String l; (l = br.readLine()) != null; ) {
                if (l.trim().replace("\"", "").equals("PROVEEDOR_PANTALLA=x11-directo")) return true;
            }
        } catch (Exception ignorada) { }
        return false;
    }

    // El servidor arranca al abrir la vista, no con la primera Surface: la vista oculta la SurfaceView mientras la
    // sesión espera su readiness, y la sesión espera el socket del servidor. El tamaño es el de la pantalla y se
    // toma una vez (no se reajusta al rotar).
    private static void iniciarX11(Activity a, String id) {
        ClienteX11.limpiarRestos(a);
        DisplayMetrics dm = a.getResources().getDisplayMetrics();
        File raiz = SistemaLinux.raiz(a, id);
        int dpi = EscalaX11.dpi(raiz, SistemaLinux.adaptador(a, id).home(raiz));
        ClienteX11.arrancar(a, id, dm.widthPixels, dm.heightPixels, dpi, null, () -> {
            // murió :x11: se cierra la vista y el escritorio de esa instancia (la próxima vez arranca otro servidor)
            a.startService(new Intent(a, TerminalService.class)
                    .setAction(TerminalService.CERRAR_ESCRITORIO)
                    .putExtra(TerminalService.EXTRA_INSTANCIA_ID, id));
            a.runOnUiThread(a::finish);
        });
    }

    // La vista de `instanciaId` da o quita su superficie. Cada vista habla de su instancia: al cambiar de escritorio la
    // vista que se va avisa después de que la nueva ya se abrió.
    static void ventana(String instanciaId, Surface surface, int ancho, int alto, int mmAncho, int mmAlto) {
        if (!Boolean.TRUE.equals(esX11Por.get(instanciaId))) {
            Wayland.ventana(surface, ancho, alto, mmAncho, mmAlto);
            return;
        }
        ClienteX11 c = ClienteX11.de(instanciaId);
        if (c != null) c.ventana(surface);
    }

    static void limpiarPantalla() {
        if (!x11) Wayland.limpiarPantalla();
    }

    static void mover(float x, float y) {
        ClienteX11 c = x11 ? ClienteX11.de(instancia) : null;
        if (c != null) c.mover(x, y); else if (!x11) Wayland.mover(x, y);
    }

    static void boton(int boton, boolean pulsado) {
        ClienteX11 c = x11 ? ClienteX11.de(instancia) : null;
        if (c != null) c.boton(boton, pulsado); else if (!x11) Wayland.boton(boton, pulsado);
    }

    static void eje(float dx, float dy) {
        ClienteX11 c = x11 ? ClienteX11.de(instancia) : null;
        if (c != null) c.eje(dx, dy); else if (!x11) Wayland.eje(dx, dy);
    }

    // Los gestos de varios dedos (zwp_pointer_gestures) no existen en X11.
    static void gesto(int fase, int dedos, float dx, float dy) {
        if (!x11) Wayland.gesto(fase, dedos, dx, dy);
    }

    static void tecla(int codigo, boolean pulsada) {
        ClienteX11 c = x11 ? ClienteX11.de(instancia) : null;
        if (c != null) c.tecla(codigo, pulsada); else if (!x11) Wayland.tecla(codigo, pulsada);
    }
}
