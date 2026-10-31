package dev.ben4shot.glibcprueba;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;

import java.util.HashMap;
import java.util.Map;
import org.junit.Test;

public class ClavePruebaTest {
    @Test
    public void ponerClaveDecodificaElBase64() {
        Map<String, String> env = new HashMap<>();
        ClavePrueba.ponerClave(env, "c2VjcmV0bw==");
        assertEquals("secreto", env.get("HUMO_CLAVE"));
    }

    @Test
    public void sinClaveNoHayVariableAunqueLaTuviera() {
        Map<String, String> env = new HashMap<>();
        env.put("HUMO_CLAVE", "heredada");
        ClavePrueba.ponerClave(env, null);
        assertFalse(env.containsKey("HUMO_CLAVE"));
    }

    @Test
    public void unBase64InvalidoNoPoneNadaNiLanzaExcepcion() {
        Map<String, String> env = new HashMap<>();
        env.put("HUMO_CLAVE", "heredada");
        ClavePrueba.ponerClave(env, "esto no es base64!!");
        assertFalse(env.containsKey("HUMO_CLAVE"));
    }

    @Test
    public void unaClaveUtf8ConEspaciosYSimbolosSaleIdentica() {
        String clave = "a b \"c\" 'd' $HOME ;rm -rf x ñ €";
        String base64 = java.util.Base64.getEncoder()
                .encodeToString(clave.getBytes(java.nio.charset.StandardCharsets.UTF_8));
        Map<String, String> env = new HashMap<>();
        ClavePrueba.ponerClave(env, base64);
        assertEquals(clave, env.get("HUMO_CLAVE"));
    }
}
