package dev.ben4shot.glibcprueba;

import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.Map;

// B93: la contraseña de sudo de las pruebas llega en base64 desde el PC (scripts/probar-en-telefono.sh) y el bash de la
// prueba la lee de HUMO_CLAVE. Solo depuración; nunca se escribe en el log.
final class ClavePrueba {
    private ClavePrueba() { }

    // Pone HUMO_CLAVE en `env` con la clave decodificada. Si no llega o no es un base64 válido no pone nada, y quita
    // cualquier HUMO_CLAVE heredada.
    static void ponerClave(Map<String, String> env, String base64) {
        env.remove("HUMO_CLAVE");
        if (base64 == null) return;
        try {
            env.put("HUMO_CLAVE", new String(Base64.getDecoder().decode(base64), StandardCharsets.UTF_8));
        } catch (IllegalArgumentException invalida) {
            // sin clave: la prueba verá que no llegó
        }
    }
}
