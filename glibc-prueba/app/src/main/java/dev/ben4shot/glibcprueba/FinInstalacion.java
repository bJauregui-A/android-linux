package dev.ben4shot.glibcprueba;

/** Qué hace la app cuando termina el instalador de una instancia; lógica pura, sin Context. */
final class FinInstalacion {
    enum Destino { ABRIR, NADA }

    private FinInstalacion() {}

    /**
     * sinPantalla: la instancia se creó para pruebas (CREAR_INSTANCIA) y no debe tocar la pantalla.
     * terminalAVista: el usuario tiene abierta la terminal del instalador, o sea que está mirando.
     */
    static Destino destino(boolean sinPantalla, boolean terminalAVista) {
        return sinPantalla && !terminalAVista ? Destino.NADA : Destino.ABRIR;
    }
}
