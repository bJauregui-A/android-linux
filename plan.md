# B85 · Sin restos de instancias borradas, e IP fijas por instancia

Como usuario, quiero que la app no deje carpetas ni IP de instancias que no existen, y que cada instancia conserve su IP, para no gastar espacio, no confundirme y tener direcciones estables.

Estado de partida (teléfono, 25-oct): carpeta suelta `files/instancias/arch-arm64`; asignación de `debian-63996 → 10.0.0.4` aunque la instancia no existe, y `debian_console-17094` recibió la misma IP; `arch-principal` no tiene IP guardada (usa 10.0.0.2 por ser la primera de la lista).

## Criterios de aceptación

1. **IP fija al crear**
   - Dado instancias con IP 10.0.0.2 y 10.0.0.4 guardadas,
   - cuando creo una instancia nueva,
   - entonces recibe 10.0.0.3 (la primera libre desde .2; la .1 es el gateway) y queda guardada.

2. **Las demás conservan su IP**
   - Dado tres instancias con .2, .3 y .4,
   - cuando borro la de .3,
   - entonces las otras siguen con .2 y .4, y la próxima instancia nueva recibe .3.

3. **Liberar la IP al borrar**
   - Dado una instancia con IP guardada,
   - cuando la borro,
   - entonces su IP desaparece de la configuración de red y del `/etc/hosts` de las demás instancias.

4. **Limpieza de IP al abrir la app**
   - Dado IP guardadas de instancias que ya no existen (como `debian-63996`),
   - cuando abro la app,
   - entonces esas IP se quitan solas, sin preguntar.

5. **Instancias sin IP guardada**
   - Dado una instancia registrada sin IP guardada (como `arch-principal`),
   - cuando abro la app,
   - entonces recibe la primera IP libre y queda guardada.

6. **Carpetas sueltas: preguntar antes de borrar**
   - Dado una carpeta en `files/instancias/` que no corresponde a ninguna instancia registrada,
   - cuando abro la lista de instancias,
   - entonces la app pregunta "Hay N carpeta(s) de instancias que ya no existen (X GB). ¿Borrarlas?"; con Sí se borran, con No quedan y vuelve a preguntar la próxima vez.

7. **Nunca borrar si la lista no es confiable**
   - Dado que la lista de instancias no se pudo leer (JSON dañado),
   - cuando abro la lista de instancias,
   - entonces no se ofrece borrar ninguna carpeta.

8. **Una instancia en creación nunca parece suelta**
   - Dado que creo una instancia,
   - entonces queda registrada antes de que exista su carpeta.

## Fuera de alcance

- Editar a mano la IP de una instancia desde la tabla de red (solo se muestra la asignada).
- Varias subredes; todo sigue en la subred por defecto (10.0.0.0/24).
- Qué pasa al llenarse la subred (más de 253 instancias).
- Reintentar si el borrado de una carpeta falla a la mitad.
- Restos fuera de `files/instancias/` (por ejemplo `files/ips/`, que ya se reescribe en cada sesión).

## Pruebas, en orden (una a la vez)

Pruebas unitarias de JVM en `app/src/test/` (JUnit 4, ya en la caché de gradle), sobre lógica sin `Context` ni `org.json`. Se corren con `./gradlew testSdk36DebugUnitTest`.

1. Primera IP libre sin asignaciones → `10.0.0.2`.
2. Primera IP libre con .2 y .4 ocupadas → `10.0.0.3` (rellena huecos).
3. Primera IP libre nunca devuelve la `.1` (gateway).
4. Asignaciones limpias: dadas asignaciones e instancias registradas, quita las de instancias inexistentes y conserva las demás con su IP.
5. Asignaciones completas: a una instancia registrada sin IP le da la primera libre, sin mover las que ya tienen.
6. Carpetas sueltas: dadas las carpetas de `files/instancias/` y las rutas registradas, devuelve solo las que sobran.
7. Carpetas sueltas con lista no confiable (no se pudo leer) → ninguna.

Integración en el código de la app (sin prueba unitaria; se comprueba en el teléfono):

8. `crearInstancia`: registrar antes de crear la carpeta y asignar con la primera IP libre (reemplaza la IP por posición de `ipParaInstancia`).
9. `eliminarInstancia`: quitar su asignación y reescribir `/etc/hosts`.
10. Al abrir la app: limpiar y completar asignaciones (pruebas 4 y 5) y reescribir `/etc/hosts`.
11. Paso mínimo de interfaz: en la lista de instancias, el diálogo de carpetas sueltas con el tamaño, Sí/No.

Comprobación final en el teléfono: `arch-principal` queda con 10.0.0.2 guardada, desaparece `debian-63996` del `/etc/hosts`, `t-1725` y `debian_console` conservan .3 y .4 (ya sin choque), y la app ofrece borrar `arch-arm64`.
