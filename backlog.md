# Backlog

Historias priorizadas, de arriba hacia abajo. Cada una entrega algo que se puede comprobar en el teléfono y hace una sola cosa.
Flujo: elegir la primera historia → `/story <ID>` (genera `plan.md` con los criterios y las pruebas) → `/pair` (TDD) → commit → borrar la historia de aquí.
El detalle técnico de los ítems anteriores (B04–B61) está en `git show c2686c1:BACKLOG.md`.

## P0 — Terminar lo que quedó a medias

- **B62** · Como usuario, quiero que una instancia nueva (Arch y Debian) tenga desde el primer arranque `sudo` real con mi contraseña, para administrarla como cualquier Linux.
  - Avance 25-oct: el instalador dejaba la regla a medias (`.nuevo` + wrapper) y sudo fallaba en terminal (`unable to allocate pty`); arreglado en `b7fb8d3` y `bffcfc2`, prueba `pruebas/sudo/instalador.sh` 8/8. Corregido a mano en `arch-principal` (sudo pide contraseña y da root, confirmado por el usuario). APK instalada 17:22. **Falta:** crear una Arch y una Debian nuevas con ＋ CREAR y comprobar sudo sin tocar nada.
- **B85** · Como usuario, quiero que la app no deje carpetas sueltas de instancias que no existen, para no gastar espacio ni confundirme (hoy quedó `files/instancias/arch-arm64` del error de la IP virtual, ya corregido en `b7fb8d3`).
- **B12** · Como usuario, quiero instalar Arch con sway desde un APK limpio y volver a abrirlo después de cerrar la app, para confiar en que la instalación funciona de punta a punta.

## P1 — Escritorios por distribución

Cada distro ofrece la lista de su instalador oficial (archinstall, tasksel, sabores de Ubuntu). Lo no probado se muestra como experimental.

- **B64** · Como usuario, quiero ver junto a cada escritorio del menú si usa Wayland o X11, para saber qué compositor voy a tener.
- **B65** · Como usuario de Arch, quiero que el menú muestre los escritorios que ofrece archinstall, con los no probados marcados como experimentales, para elegir como en una instalación real.
- **B66** · Como usuario de Debian, quiero que el menú muestre los escritorios que ofrece tasksel, instalados con paquetes de Debian, para elegir como en una instalación real.
- **B67** · Como usuario de Debian, quiero tener XFCE probado y funcionando, para contar con al menos un escritorio seguro.
- **B19** · Como usuario de Debian, quiero que `/bin`, `/sbin` y `/lib` estén unificados con `/usr` como en un Debian actual, para que los paquetes que lo asumen funcionen (lo exigen Debian 13 y Ubuntu).
- **B68** · Como usuario, quiero elegir entre Debian 12 y Debian 13 al crear una instancia, para usar la versión que necesito.
- **B69** · Como usuario, quiero crear una instancia de Ubuntu 24.04 LTS, para usar sus paquetes.
- **B70** · Como usuario, quiero elegir entre Ubuntu 24.04 y 26.04 LTS al crear una instancia de Ubuntu, para usar la versión que necesito.
- **B71** · Como usuario de Ubuntu, quiero que el menú muestre los escritorios de los sabores oficiales (Ubuntu, Kubuntu, Xubuntu, Lubuntu, MATE, Budgie, Unity, Cinnamon), para elegir como en una instalación real.
- **B72** · Como usuario de Ubuntu, quiero tener LXQt (Lubuntu) probado y funcionando, para contar con al menos un escritorio seguro.

Escritorios del instalador oficial que todavía no tenemos (uno por historia; cada uno deja de ser experimental cuando se prueba):
- **B73** · Como usuario, quiero usar GNOME.
- **B74** · Como usuario de Debian, quiero usar GNOME Flashback.
- **B75** · Como usuario, quiero usar Cinnamon.
- **B76** · Como usuario, quiero usar MATE.
- **B77** · Como usuario, quiero usar Budgie.
- **B78** · Como usuario de Debian, quiero usar LXDE.
- **B79** · Como usuario de Ubuntu, quiero usar Unity.
- **B80** · Como usuario de Arch, quiero usar i3.
- **B81** · Como usuario de Arch, quiero usar bspwm.
- **B82** · Como usuario de Arch, quiero usar awesome.
- **B83** · Como usuario de Arch, quiero usar Enlightenment.
- **B84** · Como usuario de Arch, quiero usar Deepin.

## P2 — Validar lo que ya existe

- **B10** · Como usuario, quiero que los dos escritorios que hoy quedan en negro o en gris muestren imagen, para poder elegir cualquiera de los 14.
- **B11** · Como usuario, quiero usar los escritorios X11 directos (Openbox, XFCE X11), para tener una alternativa sin Wayland.
- **B13** · Como usuario de Debian, quiero instalar herramientas de compilación y compilar un programa dentro de la instancia, para desarrollar en el teléfono.
- **B14** · Como usuario, quiero que al cerrar la sesión los programas terminen en orden, para no perder datos ni sesiones guardadas.
- **B15** · Como usuario, quiero desbloquear Phosh y COSMIC con mi contraseña, para usar esos escritorios sin quedar fuera.
- **B16** · Como desarrollador, quiero una batería de pruebas de humo que corra en una instancia (shell, paquetes, app gráfica, GPU, audio, red), para saber en un minuto si algo se rompió.
- **B17** · Como usuario, quiero que los programas en Go, Rust y los estáticos más comunes (`rg`, `fd`, `lazygit`) funcionen, para usar herramientas modernas sin recompilarlas.
- **B40** · Como usuario, quiero que `ss` liste las conexiones de mi instancia, para diagnosticar la red como en Linux.
- **B42** · Como usuario, quiero llegar a un servicio de mi instancia por `127.0.0.1`, para que los programas que asumen loopback funcionen sin configurarlos.
- **B41** · Como usuario, quiero que el menú de escritorios del instalador responda al instante, para elegir sin esperas.

## P3 — Plan vigente

- **B27a** · Como usuario, quiero que `sshd` corra como root con separación de privilegios, como en Linux, para usar la configuración oficial de OpenSSH.
- **B27b** · Como usuario, quiero que Apache atienda con sus procesos como `www-data`, para correr servidores web tal como vienen empaquetados.
- **B53** · Como usuario de Debian, quiero que la instancia traiga los usuarios de sistema estándar (`www-data`, `nobody`...) y `hostname`, para que los paquetes se instalen sin errores.
- **B23** · Como usuario, quiero que al actualizar la app mis instancias reciban la glibc y las herramientas nuevas sin reinstalarlas, para no perder lo que tengo.
- **B28** · Como usuario, quiero copiar o renombrar una instancia sin que se rompan sus enlaces, para duplicar un entorno que ya funciona (hoy los enlaces y algunas configs de la base apuntan a `files/archlinux`).
- **B22** · Como usuario, quiero exportar una instancia a un archivo y restaurarla, para tener respaldos.
- **B26b** · Como usuario, quiero que desde una instancia no se vean los archivos de las otras instancias, para mantenerlas aisladas.
- **B44** · Como usuario, quiero que la app rechace nombres de instancia inválidos (vacíos, solo puntos), para no crear instancias que rompen herramientas.
- **B47** · Como usuario, quiero que la raíz de una instancia nueva tenga los permisos correctos desde el inicio, para que `sudo mkdir /x` funcione sin arreglos al abrirla.
- **B50** · Como usuario, quiero que un servicio que falla al arrancar quede marcado como fallido sin trabar a los demás, para que el resto de la instancia siga funcionando.
- **B51** · Como usuario, quiero ver el log de `sshd` con `service logs ssh`, para entender por qué no me deja entrar.
- **B52** · Como usuario, quiero que `sshd` lo arranque un solo responsable, para que no haya dos copias peleando por el puerto.
- **B48** · Como desarrollador, quiero pruebas automáticas del supervisor que corran en el PC, para cambiarlo sin miedo.
- **B45** · Como desarrollador, quiero que una prueba compruebe que las instancias nuevas traen la glibc recién compilada, para no publicar un APK con la libc vieja.
- **B63** · Como desarrollador, quiero regenerar desde una instancia actual lo compilado en el teléfono (Mesa, wlroots, sway, mesa-gl), para poder rearmar el APK si se pierde `trabajo/compilados.tar`.
- **B20** · Como usuario, quiero crear una instancia a partir de un Dockerfile, para reproducir entornos declarados.
- **B24a** · Como usuario, quiero que los programas que usan colas de mensajes SysV funcionen, para no quedar fuera por esa falta.
- **B24b** · Como usuario, quiero que la memoria compartida no ocupe disco ni deje basura al cerrarse los programas, para no llenar el almacenamiento.
- **B25** · Como desarrollador, quiero pasar los parches a la próxima glibc de Arch ARM, para seguir instalando paquetes nuevos.

## P4 — Escritorio completo e integración con Android

- **B30** · Como usuario, quiero ver la batería real del teléfono en la barra del escritorio, para saber cuánta carga me queda.
- **B31** · Como usuario, quiero que KDE, COSMIC y los bloqueadores encuentren un gestor de sesión mínimo, para que no fallen las funciones que lo piden.
- **B32** · Como usuario, quiero que el selector de archivos y la apertura de enlaces de las apps funcionen por el portal estándar, para usar apps empaquetadas modernas.
- **B33** · Como usuario, quiero capturar el mouse en juegos y apps 3D, para controlarlos con movimiento relativo.
- **B34** · Como usuario, quiero escribir con el teclado de Android con autocorrector y predicción, para escribir rápido en apps Linux.
- **B35** · Como usuario, quiero usar el lápiz con presión e inclinación, para dibujar en Krita o Xournal++.
- **B36** · Como usuario, quiero OpenGL por GPU en X11 sin copias a la CPU, para que las apps X11 rindan como las Wayland.
- **B37** · Como usuario, quiero que cada ventana Linux sea una ventana de Android, para usar recientes, pantalla dividida y ventanas flotantes.
- **B38** · Como usuario, quiero un cursor de tamaño legible en el teléfono, para ver dónde apunto.
- **B39** · Como usuario, quiero que las notificaciones, abrir enlaces y `/sdcard` funcionen en todos los escritorios, no solo en sway.
