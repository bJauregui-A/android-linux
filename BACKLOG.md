# Backlog

Lista priorizada de lo pendiente. `NOTAS.md` es la bitácora (qué pasó); esto es **qué falta**.
Al cerrar un ítem: marcarlo `[x]`, anotar la sesión y moverlo a "Hecho" al final.

Prioridad: **P0** bloquea o deja algo a medias · **P1** validar lo que ya existe · **P2** plan vigente · **P3** integración con Android · **P4** juegos · **P5** proyecto/publicación.
Origen: sesión de NOTAS (`76ª`), sección de `PROYECTO.md` o revisión del 2026-10-25.

## P0 — Cerrar lo que quedó a medias

- [x] **B01 · Decidir el retiro de SteamOS Holo (cambios sin commit del 25-oct).** El diff saca `[holo-core]`/`[holo-extra]` y `pacman-xfer` de `bootstrap.py`, `capa.py` e `instalar.sh`, pero:
  - Hecho 25-oct: retirado Holo por completo (pacman-xfer, bloques muertos); firmas de Arch ARM verificadas (sin SigLevel global).
  - `apk/primer-arranque.sh:70-72` todavía busca `[holo-core]` (código muerto) y `apk/pacman-xfer` sigue en el repo.
  - `instalar.sh` y `bootstrap.py` ponen `SigLevel = Never` **global**: Arch ARM deja de verificar firmas (deshace el modelo granular de la 70ª, que dejaba `Required DatabaseOptional` para `core`/`extra`). Propuesta: volver a `Required DatabaseOptional`.
- [x] **B02 · Recuadros del instalador desalineados.** Los bordes se acortaron a 52 `─` pero las líneas interiores siguen rellenas para 60: el `│` derecho queda ~8 columnas afuera (`primer-arranque.sh`, `instalar.sh`). Ajustar el relleno o calcularlo con `printf %-Ns`.
  - Hecho 25-oct: recuadros con ancho real de la terminal (caja_sup/lin/med/inf, tput/stty, 60 de respaldo).
- [x] **B03 · Regenerar capa/base y APK tras B01–B02.** `capa.tgz` y la APK son del 23-oct; los scripts cambiaron el 25-oct (regla de AGENTS.md: nada a medias). `apk/armar.sh sdk36` → Gradle → instalar desde el PC.
  - Hecho 25-oct: armar.sh + assembleSdk36Debug hechos; falta instalar desde el PC.
- [ ] **B04 · Probar la terminal de Debian por `libldp.so`** (cambio sin commit en `AdaptadorDebianArm64.comandoTerminal` y la consola de `SistemaActivity`, que además ahora llama `agregarEntorno`).
- [ ] **B05 · Decidir qué archivos nuevos entran al repo:** `.claude/`, `.codex/`, `.gemini/`, `.agents/`, `.mcp.json`, `.vscode/`, `.graphifyignore`, `practica/`, `transcripcion_android_linux.txt`. Agregar `.codegraph/` y `graphify-out/` a `.gitignore`.
- [ ] **B06 · Poner al día `PROYECTO.md`:** "Para retomar" dice 2026-10-22; "Próximos pasos" está obsoleto (los binarios estáticos ya están, 0023). Considerar archivar las sesiones viejas de `NOTAS.md` (884 líneas).

## P1 — Validar lo que ya existe

- [ ] **B10 · Re-verificar que los 13 escritorios además de Hyprland muestran imagen y toman entrada.** El "14/14" de la 52ª solo comprobaba proceso y socket; Hyprland estaba en negro hasta la 53ª.
- [ ] **B11 · Validar los perfiles X11 directo** (`openbox`, `xfce-x11`, proveedor `x11-directo`): creados en la 74ª, sin probar en el teléfono.
- [ ] **B12 · Instalación de Arch desde cero, de punta a punta**, con APK limpia: extracción, asistente, paquetes, primer arranque de sway, cerrar y reabrir la app.
- [ ] **B13 · Debian: `apt-get install build-essential git python3`** y compilar algo dentro (plan 76ª, punto 2).
- [ ] **B14 · Confirmar audio, portapapeles y cierre ordenado** con el usuario (quedó "falta confirmar" desde la 36ª–40ª).
- [ ] **B15 · Desbloqueo con contraseña** en Phosh/COSMIC y login SSH con la contraseña del instalador.
- [ ] **B16 · Batería de pruebas de humo automatizada** (script en el teléfono): shell, `pacman -Sy`/`apt update`, app GTK, `vkcube`, `es2gears`, audio, red virtual entre instancias, cerrar y reabrir. Base para no romper nada al seguir.

## P2 — Plan vigente (nuevas capacidades)

- [ ] **B20 · Instancias desde Dockerfile / OCI** (plan 76ª, punto 1): intérprete de `FROM`/`ENV`/`COPY`/`RUN` e importación de tarballs OCI con la glibc propia.
- [ ] **B21 · Adaptador Ubuntu ARM64** (reusar `bootstrap-debian.py`).
- [ ] **B22 · Respaldo / exportar / restaurar una instancia** (y recuperación tras instalación fallida).
- [ ] **B23 · Actualizar el runtime sin reinstalar** (libc/capa nueva sobre instancias existentes, con respaldo `libc.so.6.00NN`).
- [ ] **B24 · Colas de mensajes SysV (`msg*`)** y `/dev/shm` en memfd (PROYECTO, compatibilidad 6 y pendiente 9).
- [ ] **B25 · Rebase de los parches de glibc** a la próxima glibc de Arch ARM (compatibilidad 9).

## P3 — Integración con Android

- [ ] **B30 · Notificaciones** D-Bus → Android.
- [ ] **B31 · `xdg-open` → intents** y acceso a `/sdcard`.
- [ ] **B32 · Teclado de Android de verdad:** `text-input-v3` ↔ `InputConnection` (autocorrector, predicción).
- [ ] **B33 · Hardware sintético:** batería (`BatteryManager`), sensores.
- [ ] **B34 · Cada ventana Linux = ventana Android** (recientes, pantalla dividida, flotante).
- [ ] **B35 · Revisar si siguen pendientes:** popups xdg (menús GTK/Qt), cursor más grande, opacidad de inactivas, SUPER+V (cliphist).

## P4 — Juegos

- [ ] **B40 · Mandos en Wine:** `winedevice.exe` abre `event0` y lo cierra (17ª). Luego vibración (EV_FF) y varios mandos.
- [ ] **B41 · Diálogos de Steam (CEF) no toman clics** (Propiedades del juego).
- [ ] **B42 · Evitar la copia por CPU en X11:** `winewayland.drv` o MIT-SHM sin DRI3.
- [ ] **B43 · DXVK en Lutris** (hoy WineD3D) y medir FPS reales con `DXVK_HUD`.
- [ ] **B44 · Un emulador nativo ARM64 de punta a punta** (RetroArch/Dolphin/PPSSPP) con audio y mando.

## P5 — Proyecto y publicación

- [ ] **B50 · README público:** arquitectura, requisitos, dispositivos probados (Redmi 15 5G, Xiaomi 12T Pro), estado y límites.
- [ ] **B51 · Licencia explícita.**
- [ ] **B52 · Separar resultados medidos de objetivos**, con versiones exactas (Android, Mesa, glibc, parches) y comandos para reproducir.

## Debloat

- [ ] **B60 · Checklist "Pendiente de probar"** de `NOTAS.md` (reinicio, video en Galería, links → Edge, Facebook/Messenger).
- [ ] **B61 · Limpiar la barra de estado.**

## Hecho

_(mover aquí los ítems cerrados, con la sesión)_
