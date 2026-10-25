# B29 · Correr pruebas dentro de la app desde el PC

Historia para la sesión de código. Escrita el 2026-10-25. Leer antes `AGENTS.md`. Es la base del TDD en el teléfono: B26 (`pruebas/raiz/en-telefono.sh`), B16 (batería de humo) y B27 la necesitan.

## Historia

**Como** agente o desarrollador trabajando desde el PC,
**quiero** correr un script de prueba **dentro del contexto real de la app** (mismo proceso de zygote, mismo seccomp, misma glibc) en una instancia elegida, y recibir su salida y su código de salida,
**para** escribir pruebas en rojo y verlas pasar a verde sin pedirle al usuario que escriba en el teléfono.

## Por qué hace falta (comprobado el 25-oct)

| Camino | Por qué no sirve |
|---|---|
| `adb shell`, `run-as`, `app_process` | Corren **sin** el seccomp de apps (lo pone zygote al crear el proceso de la app): `openat2` y otras syscalls pasarían, y la prueba engañaría |
| `adb shell input text` | HyperOS lo bloquea (`INJECT_EVENTS`) sin "Depuración USB (ajustes de seguridad)"; además escribe en lo que el usuario tenga abierto |
| SSH a la instancia (8022) | Solo si la instancia tiene `sshd` corriendo y acepta la clave del PC; hoy no pasa (el 8022 cerró sin saludo) |
| `am instrument` | Reinicia el proceso de la app por defecto: mata las sesiones del usuario |

Lo que sí funciona: un proceso lanzado **por la propia app** con `ProcessBuilder` (como `linuxPara`) hereda el seccomp de zygote. La prueba de `openat2` lo confirmó: desde la terminal de la app, `Seccomp: 2` y ENOSYS; desde el PC, OK.

## Diseño

### Componentes

1. **Receptor solo para depuración: `ReceptorPruebas`**, en el source set `src/debug/` (`java/` + `AndroidManifest.xml` que se fusiona). Así existe en `sdk36Debug`, `sdk28Debug` y `pruebaDebug`, y **no** en `diagnostico` ni en un futuro release.
   - `android:exported="true"` **con** `android:permission="android.permission.DUMP"`. El usuario `shell` (adb) tiene `DUMP`; las apps normales no pueden obtenerlo (es `signature|privileged|development`). Así solo adb (o el sistema) puede dispararlo.
   - Acción: `dev.ben4shot.glibcprueba.PRUEBA`. Extras: `instancia` (id, obligatorio), `script` (ruta Linux dentro de la instancia, obligatorio), `id` (nombre de la corrida, obligatorio, `[a-z0-9-]+`), `limite` (segundos, por defecto 300).
   - Se dispara desde el PC con un broadcast explícito:
     ```
     adb shell am broadcast -n dev.ben4shot.glibcprueba.sdk36/dev.ben4shot.glibcprueba.ReceptorPruebas \
       -a dev.ben4shot.glibcprueba.PRUEBA --es instancia dev-6918 --es script /tmp/prueba.sh --es id raiz-1
     ```
2. **Ejecución:** el receptor no corre la prueba él mismo (un `BroadcastReceiver` tiene unos 10 s). Le pasa el pedido a `TerminalService` con una acción nueva, `EJECUTAR_PRUEBA`, y el servicio:
   - Comprueba que la acción solo se acepte con `BuildConfig.DEBUG` (en otra build se ignora y se registra en el log).
   - Lanza `linuxPara(instancia, "/usr/bin/bash", script)` en un hilo, con el entorno completo de la instancia (`GLIBC_PREFIX`, cargador, PATH...). No abre actividades, no cambia el foco, no inicia el escritorio.
   - Mata el proceso (y su grupo) al pasar `limite`. Código 124, como `timeout`.
3. **Resultado**, en `files/pruebas/<id>/` (fuera de las instancias, legible por `run-as`):
   - `salida.log`: stdout y stderr juntos, en orden.
   - `codigo`: código de salida (se escribe **al final**).
   - `estado`: `corriendo` → `terminado` | `limite` | `error: <motivo>`.
   - Errores sin lanzar nada (`error: ...` y `codigo` = 2): instancia inexistente o no instalada, script inexistente, `id` inválido o repetido mientras corre.
4. **Lado PC: `scripts/probar-en-telefono.sh <instancia> <script-local> [limite]`**
   - Sube el script a `<instancia>/tmp/prueba-<id>.sh` por `run-as` (base64, como se hizo a mano el 25-oct).
   - Lanza el broadcast, espera `codigo` (consulta cada 1 s; tope = `limite` + 15 s), imprime `salida.log` y **sale con el mismo código** que el script.
   - Al final borra el script subido y `files/pruebas/<id>/` (opción `--conservar` para no borrar).
   - Si el broadcast no llega (APK sin el receptor, app sin servicio), lo dice claro y sale con 3.

### Servicio en segundo plano

Android limita que una app en segundo plano inicie servicios. El caso normal es que el usuario tenga una sesión abierta (`TerminalService` ya está en primer plano) y ahí no hay problema. Si **no** hay servicio corriendo, hay que comprobar en el teléfono qué deja hacer Android 16 / HyperOS desde un broadcast:

- a) `startForegroundService` desde el receptor (los broadcasts explícitos de `shell` pueden dar la exención temporal de segundo plano), o
- b) si no se permite: `estado` = `error: sin servicio`, y `probar-en-telefono.sh` ofrece `--abrir`, que primero hace `am start` de la app (eso sí cambia lo que se ve en pantalla; solo con permiso del usuario).

Documentar en `NOTAS.md` cuál de las dos funcionó.

### Seguridad

- Es solo para builds de depuración. Una app *debuggable* ya deja a adb ejecutar código como la app (`run-as`), así que **no agrega un poder nuevo**: solo lo hace correr con el seccomp correcto.
- El permiso `DUMP` impide que otra app instalada lo dispare.

## Plan (pruebas primero)

1. **Autoprueba en rojo:** `pruebas/intent/autoprueba.sh` en el PC, que llama a `scripts/probar-en-telefono.sh` con pequeños scripts de caso (A1–A9 abajo) y compara la salida y el código. Falla porque no existen ni el receptor ni el script de PC.
2. `scripts/probar-en-telefono.sh` (lado PC).
3. `src/debug/AndroidManifest.xml` + `src/debug/java/.../ReceptorPruebas.java`.
4. Acción `EJECUTAR_PRUEBA` en `TerminalService` (con `BuildConfig.DEBUG`), límite de tiempo y escritura de `files/pruebas/<id>/`.
5. Compilar `assembleSdk36Debug` e instalar **desde el PC** (`adb install -r`: mata las sesiones abiertas; avisar al usuario antes).
6. Autoprueba en verde. Resolver el punto "servicio en segundo plano" y anotarlo.
7. Usarlo de verdad: correr `pruebas/raiz/en-telefono.sh` de B26 con esto.
8. `NOTAS.md` (cómo se usa y qué pasó con el segundo plano), `PROYECTO.md` (tabla de archivos) y `AGENTS.md` (sección "Dónde corres": cómo probar dentro de la app desde el PC). Marcar B29 en `BACKLOG.md`.

## Criterios de aceptación

### Autoprueba (`pruebas/intent/autoprueba.sh`, desde el PC, con una sesión abierta en el teléfono)

| # | Script de caso | Esperado |
|---|---|---|
| A1 | `echo hola` | imprime `hola`, código 0 |
| A2 | `exit 7` | código 7 (no 3: ese es el de "no llegó a la app") |
| A3 | `echo a; echo b >&2; echo c` | `a`, `b`, `c` en ese orden |
| A4 | `cat /proc/self/attr/current; grep Seccomp /proc/self/status` | contexto `untrusted_app` y `Seccomp: 2` (**es el contexto de la app**) |
| A5 | `cat /etc/os-release; echo $GLIBC_PREFIX` | el os-release de **esa** instancia y su prefijo (probar con una Arch y una Debian) |
| A6 | `sleep 30` con `limite` = 5 | código 124 en ~5 s; el proceso ya no existe (`ps` por adb) |
| A7 | instancia `no-existe` | código 2, `error: instancia` |
| A8 | dos corridas con `id` distinto a la vez | las dos terminan con su propia salida |
| A9 | python con `openat2` (el script de `o2.py` del 25-oct) | `Function not implemented` (en el PC daría OK: confirma el seccomp) |

### Del componente

- **C1 Sin tocar al usuario:** durante A1–A9 no cambia la actividad al frente (`dumpsys window | grep mCurrentFocus` antes y después) y no aparece nada en pantalla.
- **C2 Solo adb:** un broadcast enviado sin `DUMP` (por ejemplo `run-as <app> am broadcast ...`, que corre con el UID de la app) **no** se entrega: no aparece `files/pruebas/<id>/`.
- **C3 Solo depuración:** el APK `diagnostico` no tiene `ReceptorPruebas` (`aapt2 dump xmltree --file AndroidManifest.xml <apk>` o `apkanalyzer manifest print`).
- **C4 Uso real:** `scripts/probar-en-telefono.sh dev-6918 glibc-prueba/pruebas/raiz/en-telefono.sh` corre la prueba de B26 y devuelve su código.
- **C5 Limpieza:** después de una corrida sin `--conservar` no quedan el script subido ni `files/pruebas/<id>/`.

### De entrega (Definition of Done)

- Autoprueba verde (salida pegada en `NOTAS.md`), C1–C5 comprobados.
- `AGENTS.md` explica cómo probar dentro de la app desde el PC.
- Commit.

## Fuera de alcance

- Contenido de la batería de humo (eso es B16): aquí solo el mecanismo.
- Pruebas gráficas (capturas, input al compositor, escritorios).
- Instalar o actualizar la APK automáticamente.
- Correr pruebas sin una instancia instalada, o crear o borrar instancias.
- CI en la nube.
- Cualquier cambio de comportamiento en builds que no sean de depuración.

## Riesgos

- **Segundo plano en Android 16 / HyperOS** (ver arriba): puede obligar a tener una sesión abierta.
- **`entorno()` tiene efectos:** prepara `resolv.conf`, la IP virtual y los puentes (`Wayland.iniciarPara`, `Abrir`, `Notificar`, `PuertoAdb`). Es lo mismo que pasa al abrir una terminal, pero conviene revisar que una prueba sin escritorio no deje servicios colgando.
- **Reinstalar la APK** para ponerlo en marcha cierra las sesiones del usuario: coordinar.
