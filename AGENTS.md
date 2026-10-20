# Contexto para agentes (Claude Code, agy)

Proyecto: Linux real (Arch ARM con glibc propia, sin root ni proot) dentro de una app de Android, con escritorio sway por GPU. Teléfono: Redmi 15 5G (HyperOS 3, Android 16, bootloader bloqueado). Además está el registro del debloat en `debloat/`.

## Leer primero
1. `NOTAS.md` — bitácora por sesión; el plan vigente está en "Siguiente sesión (Nª)" (el número más alto).
2. `glibc-prueba/PROYECTO.md` — "Objetivo principal", "Para retomar" y "Archivos".

## Dónde corres
- **En el PC** (repo original): el teléfono se maneja por `adb` y por SSH (`adb forward tcp:8022 tcp:8022`, `ssh -p 8022 user@127.0.0.1`).
- **Dentro del teléfono** (Claude Code o agy en kitty, dentro de sway): ya estás en el Arch de la app. No hay `adb` y casi todo lo que las notas hacen "por SSH" se corre directo. Ojo: **tú mismo corres dentro de la app**, así que reiniciar sway, hacer `am force-stop`, reinstalar el APK o instalar una libc nueva (`instalar-glibc.sh`) **te mata la sesión**. Eso se hace desde el PC, o se le pide al usuario.
- Lo generado (`~/mesa-gl`, `~/sway`, `~/wlroots`, `~/turnip-x11`...) vive en el home del teléfono, no en el repo; el repo tiene los parches y scripts para rehacerlo.

## Reglas de trabajo
- Conversación en español.
- Antes de un comando largo o que modifique algo en el teléfono, decir en una línea qué hace y si es solo lectura. Nunca borrar datos de apps sin confirmación.
- Hablar de lo técnicamente posible; no revisar políticas de HyperOS ni licencias.
- Todo reversible; no poner en riesgo las apps bancarias (por eso no hay root ni bootloader abierto).
- Probar una libc nueva aislada antes de instalarla, y dejar respaldo (`libc.so.6.00NN`). No forzar cambios de render sin probarlos en una instancia aparte.
- No mandar teclas/toques mientras el usuario juega o usa el teléfono. Capturas con `grim` dentro de sway, nunca `screencap` con la app en segundo plano (captura chats privados).
- Cerrar Steam en orden: `swaymsg exec "steam -shutdown"`.
- Al terminar una sesión, actualizar `NOTAS.md` (y `PROYECTO.md` si cambia el estado) y hacer commit.
