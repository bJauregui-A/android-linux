package dev.ben4shot.glibcprueba;

import android.content.Context;

// Opciones de la app (⚙ OPCIONES en el inicio). Se guardan en las preferencias "opciones".
final class Opciones {
    private static final String PREF = "opciones";

    // Qué suena cuando no hay ningún escritorio al frente (la app en segundo plano o en el inicio).
    static final String AUDIO_FONDO = "audio_fondo";
    static final String AUDIO_SILENCIO = "silencio";
    static final String AUDIO_ULTIMA_VISTA = "ultima_vista";

    // Qué hace un escritorio cuando su vista se va: sigue corriendo sin dibujar, o se pausa entero (Pausa).
    static final String AL_SALIR = "al_salir";
    static final String SALIR_SIN_DIBUJAR = "sin_dibujar";
    static final String SALIR_PAUSAR = "pausar";

    private Opciones() { }

    static String alSalir(Context c) {
        return c.getSharedPreferences(PREF, Context.MODE_PRIVATE).getString(AL_SALIR, SALIR_SIN_DIBUJAR);
    }

    static void alSalir(Context c, String valor) {
        c.getSharedPreferences(PREF, Context.MODE_PRIVATE).edit().putString(AL_SALIR, valor).apply();
    }

    static boolean pausaAlSalir(String alSalir) {
        return SALIR_PAUSAR.equals(alSalir);
    }

    static String audioFondo(Context c) {
        return c.getSharedPreferences(PREF, Context.MODE_PRIVATE).getString(AUDIO_FONDO, AUDIO_SILENCIO);
    }

    static void audioFondo(Context c, String valor) {
        c.getSharedPreferences(PREF, Context.MODE_PRIVATE).edit().putString(AUDIO_FONDO, valor).apply();
    }

    // Solo suena una instancia: la del escritorio al frente; sin ninguno, la última vista si así se eligió.
    static String instanciaQueSuena(String audioFondo, String alFrente, String ultimaVista) {
        if (alFrente != null) return alFrente;
        return AUDIO_ULTIMA_VISTA.equals(audioFondo) ? ultimaVista : null;
    }

    // Una instancia pausada no suena: lo que quedó en su FIFO es un resto de antes de la pausa.
    static String instanciaQueSuena(String audioFondo, String alFrente, String ultimaVista,
                                    java.util.Set<String> pausadas) {
        String s = instanciaQueSuena(audioFondo, alFrente, ultimaVista);
        return s != null && pausadas.contains(s) ? null : s;
    }
}
