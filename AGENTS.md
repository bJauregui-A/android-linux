# Contexto para agentes (Claude Code, agy)

Proyecto: Linux real (Arch ARM y Debian con glibc propia, sin root ni proot) dentro de una app de Android, con escritorios por GPU. Teléfono: Redmi 15 5G (HyperOS 3, Android 16, bootloader bloqueado). El registro del debloat está en `debloat/`.

## Leer primero
1. `README.md`: cómo funciona, estructura del repo, cómo compilar e instalar, pruebas y trampas conocidas.
2. `backlog.md`: lo pendiente, en historias priorizadas. Si existe `plan.md`, es la historia en curso.

## Cómo se trabaja (TDD)
- `/backlog`: definir o ajustar historias en `backlog.md` (cortas, una sola cosa cada una, sin detalle técnico).
- `/story <ID>`: refinar una historia → `plan.md` (criterios Dado/Cuando/Entonces, fuera de alcance, lista de pruebas en orden).
- `/pair`: implementar `plan.md` en rojo → verde → refactor, **una prueba a la vez**, esperando revisión entre pasos. No modificar ni borrar una prueba para que pase.
- Al cerrar una historia: commit, borrar la historia de `backlog.md` y `plan.md`. La historia queda en `git log`; no hay bitácora aparte.
- Las pruebas viven en `glibc-prueba/pruebas/<tema>/`. Las de syscalls se corren dentro de la app con `scripts/probar-en-telefono.sh`; `adb shell` y `run-as` no tienen el seccomp de la app.

## Dónde corres
- **En el PC** (repo original): el teléfono se maneja por `adb` y por SSH (`adb forward tcp:8022 tcp:8022`, `ssh -p 8022 user@127.0.0.1`).
- **Dentro del teléfono** (en kitty, dentro de un escritorio): ya estás en una instancia de la app. Hay `adb` local (depuración inalámbrica a `127.0.0.1`; se reconecta con `adb-conectar` y se cae sin wifi o al reiniciar). Da nivel `shell` sobre Android, así que las reglas de abajo aplican igual. Ojo: **tú mismo corres dentro de la app** (`dev.ben4shot.glibcprueba.sdk36`): `am force-stop`, `pm` sobre la app, reinstalar el APK, reiniciar el compositor o instalar una libc en tu instancia **te matan la sesión** (y todo lo que el usuario tiene abierto). Eso se hace desde el PC o se le pide al usuario.
- **Probar dentro de la app desde el PC**: `glibc-prueba/scripts/probar-en-telefono.sh [--conservar] <instancia> <script> [límite]` (sale con 3 si no llegó). Necesita un APK de depuración **y una sesión de la app abierta**: `adb shell am start -n dev.ben4shot.glibcprueba.sdk36/dev.ben4shot.glibcprueba.TerminalActivity` (cambia lo que se ve en pantalla). Para instalar una libc nueva en una sola instancia: `glibc-prueba/scripts/instalar-libc-en-instancia.sh <instancia>` (con respaldo y `--revertir`).
- Lo compilado en el teléfono (`~/mesa-gl`, `~/sway`, `~/wlroots`, `~/turnip`...) vive en el home de la instancia, no en el repo. El repo tiene los parches y las recetas para rehacerlo.

## Reglas de trabajo
- Conversación en español.
- Antes de un comando largo o que modifique algo en el teléfono, decir en una línea qué hace y si es solo lectura. Nunca borrar datos de apps sin confirmación.
- Hablar de lo técnicamente posible; no revisar políticas de HyperOS ni licencias.
- Todo reversible; no poner en riesgo las apps bancarias (por eso no hay root ni bootloader abierto).
- Probar una libc nueva aislada antes de instalarla, y dejar respaldo. No forzar cambios de render sin probarlos en una instancia aparte.
- **Binarios y bibliotecas compiladas**: cada cambio en los binarios o bibliotecas nativas (`libldp.so`, `libc.so.6`, shims...) se vuelve a empaquetar en el APK (`jniLibs`, `apk/armar.sh`) y se sincroniza a las instancias del teléfono. Nunca dejar el binario solo en `build/` o a medias en `jniLibs`.
- No mandar teclas ni toques mientras el usuario usa el teléfono. Las capturas se hacen con `grim` dentro del escritorio, nunca con `screencap` con la app en segundo plano (captura chats privados).
- Si cambia algo de lo que describe `README.md` (arquitectura, comandos, trampas), actualizarlo en el mismo commit.

<!-- CODEGRAPH_START -->
## CodeGraph

In repositories indexed by CodeGraph (a `.codegraph/` directory exists at the repo root), reach for it BEFORE grep/find or reading files when you need to understand or locate code:

- **MCP tool** (when available): `codegraph_explore` answers most code questions in one call — the relevant symbols' verbatim source plus the call paths between them, including dynamic-dispatch hops grep can't follow. Name a file or symbol in the query to read its current line-numbered source. If it's listed but deferred, load it by name via tool search.
- **Shell** (always works): `codegraph explore "<symbol names or question>"` prints the same output.

If there is no `.codegraph/` directory, skip CodeGraph entirely — indexing is the user's decision.
<!-- CODEGRAPH_END -->
