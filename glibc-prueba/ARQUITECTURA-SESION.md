# Arquitectura de sistemas y sesiones gráficas

## Objetivo

Ofrecer dentro de la app instalaciones Linux ARM64 con recetas explícitas por distribución y
entorno gráfico. No se intentará reproducir de forma universal el login de un Linux de escritorio:
cada combinación instala sus paquetes, aplica sus configuraciones y arranca con el método que sí
funciona en ese entorno. La app seguirá siendo un cliente sin root; Android conserva el control del
hardware y un supervisor pequeño común mantiene la superficie, el ciclo de vida y los puentes.

Distribución, escritorio y servidor gráfico son elecciones independientes:

```text
instalación Linux (Arch / Debian / Ubuntu)
    └── sesión (KDE / GNOME / XFCE / sway / ...)
          └── servidor gráfico (Wayland anidado / X11 anidado)
                └── superficie y entrada de Android
```

La selección efectiva de instalación es el par **sistema + escritorio** (por ejemplo,
`arch-arm64 + sway` o `debian-arm64 + xfce`). Su receta puede declarar un backend gráfico, pero no
se presupone un gestor de login, systemd, logind ni un mismo orden de arranque para todos. El
supervisor común consume solo el contrato mínimo que la app necesita.

## Receta por sistema y escritorio

La instalación resuelve primero la receta de la distribución (rootfs, gestor de paquetes,
dependencias base y rutas) y luego la receta del escritorio (paquetes para esa distribución,
archivos de configuración, variables, pasos de preparación y comando de inicio). La combinación
se valida y se aplica durante la instalación o al cambiar de escritorio; no se reescribe la
configuración del usuario cada vez que abre la app. Una receta puede usar servicios/buses propios o
no tenerlos; los requisitos se expresan explícitamente y no se inventan servicios para imitar un
Linux completo.

El primer paso implementado conserva el instalador Arch existente: `primer-arranque.sh` aplica el
overlay `escritorios/<id>/home` al elegir el perfil (sin pisar archivos existentes), sustituye
`@ESCALA@` y registra `arch-arm64:<id>` en `receta-aplicada`. Debian y Ubuntu aún no tienen receta
ni instalador. Sway sigue siendo la combinación de referencia probada; la selección de cualquier
otro perfil no convierte su estado `sin-probar` en una garantía.

El selector de sistema ya es la entrada del ícono de la app. El registro inicial mantiene el
prefijo histórico de Arch y muestra Debian/Ubuntu como no disponibles; todavía no permite crear
instalaciones nuevas ni cambia la sesión de Arch existente.

## Flujo de una sesión

El flujo objetivo, equivalente en sus contratos visibles a una sesión de escritorio, es:

1. Android inicia el servicio de la app y entrega una superficie, entrada, audio, almacenamiento
   y capacidades disponibles.
2. Un registro de instalaciones selecciona el rootfs y su adaptador de distribución. Se preparan
   usuario, grupos, `/tmp`, `/run/user/$UID`, `/dev`, `/proc`, `/sys` y las variables de entorno.
3. Se inicia el gestor de servicios de usuario; se intenta el `systemd --user` real mediante
   `GLIBC_LOADER`, para que sus ejecutables y accesos a rutas atraviesen la capa Linux de la
   instalación. Se considera listo solo cuando posee `org.freedesktop.systemd1` en el bus de esta
   sesión. Si no arranca, los perfiles que lo requieren pasan por el mismo supervisor al rescate.
   El bus D-Bus de sistema se inicia solo si un servicio lo requiere.
4. Se crea un único bus D-Bus de sesión para esa sesión gráfica. Se publican en él las variables
   de pantalla/runtime antes de activar servicios D-Bus.
5. Se inicia el proveedor de pantalla seleccionado (Wayland o X11 anidado) y se espera su estado
   de listo, no solo que el proceso siga vivo.
6. Se inicia la sesión del escritorio con el entorno de pantalla, compositor, D-Bus, portales y
   servicios auxiliares ya definidos.
7. Al cerrar, se detiene el escritorio y luego los servicios de usuario en orden inverso. Android
   puede suspender la app; una reanudación debe reconectar a la misma instalación sin dejar
   sockets o procesos huérfanos.

El host (`TerminalService`) lanza `sesion-android` con una marca para que el perfil de login no
cree un bus persistente. El supervisor envuelve la sesión con `dbus-run-session`, guarda su
dirección mientras vive y, al detectar el endpoint definido por el proveedor, actualiza el entorno
de activación D-Bus con las variables de pantalla y el escritorio. TerminalService consulta el
descriptor `linux-session.properties` para conectar procesos Linux posteriores. Este publica
protocolo, variable de conexión, endpoint y capacidades, así el host Android no presupone
`WAYLAND_DISPLAY`. El marcador específico del proveedor sigue sirviendo para readiness. Después
inicia `autostart-android`, que mantiene los PID
de los servicios que creó; al cerrar, pide al compositor compatible que cierre Steam ordenadamente y termina los
servicios antes de señalizar al compositor. `dbus-run-session` destruye el bus al salir.

Esto implementa un bus **de sesión** y, si puede arrancar, el `systemd --user` real conectado a ese
bus. El activador D-Bus del sistema para `org.freedesktop.systemd1` puede apuntar a `/bin/false`;
por eso el supervisor inicia primero el user manager y espera su propiedad del nombre. No se inicia
un bus D-Bus **de sistema** ni se afirma que exista systemd de sistema o logind. `autostart-android`
espera el ping del bus y hace comprobaciones de readiness para SSH (puerto), PipeWire (`pw-cli`) y
PulseAudio (`pactl`); otros procesos quedan marcados como comprobados por vida del PID. Mantiene un
log por servicio en `/tmp/linux-session-services/` y un resumen con tiempos y estados en
`/tmp/autostart-android.log`. Una falla de readiness termina solo ese servicio. Falta validar este
comportamiento en el dispositivo. El perfil D-Bus de login conserva un bus de rescate para la
terminal cuando no hay sesión gráfica.

## Capas y contratos

### Android host

Es propietario de la Activity/superficie y traduce eventos Android a una pantalla anidada. Declara
capacidades reales disponibles: Wayland host, acceso a GPU por KGSL/AHardwareBuffer, input,
portapapeles, audio, red y almacenamiento. No declara capacidades que Android no concede.

### Instalación Linux

Cada instalación tiene ID estable, arquitectura, ruta raíz, usuario, metadatos de distribución,
versiones, gestor de paquetes y runtime ABI. En la primera etapa habrá una sola entrada: Arch
existente. Debian y Ubuntu serán instalaciones separadas con rootfs y base de paquetes propios; no
se mezclan `/usr`, `/etc`, `/var` ni bases dpkg/pacman.

El adaptador de distribución resuelve bootstrap, paquetes, grupos y diferencias de configuración.
El selector no debe invocar `pacman` directamente ni asumir rutas exclusivas de Arch. La glibc
parchada actual es parte del runtime Arch: compartirla con Debian/Ubuntu queda condicionado a una
prueba ABI/NSS por distribución; no se debe presuponer.

### Gestor de sesión y servicios

Debe ofrecer operaciones equivalentes a iniciar, consultar estado, reiniciar y detener servicios,
con logs por unidad. El supervisor intenta ejecutar el `systemd --user` real mediante `GLIBC_LOADER`
sin privilegios Android ni cgroups delegados. La documentación de systemd describe el user manager
como iniciado usualmente por el system manager mediante `user@UID.service`, y al login manager como
quien activa `graphical-session.target`; aquí se importa el entorno e inicia ese target desde la
sesión, ciclo que falta probar en dispositivo ([user manager](https://www.freedesktop.org/software/systemd/man/latest/user%40.service.html),
[ciclo de arranque](https://freedesktop.org/software/systemd/man/latest/bootup.html)). Si una función
requiere cgroups, namespaces, mounts o acceso root, se declarará no disponible. Un supervisor
alternativo puede iniciar procesos, pero no se anunciará como `systemd1` completo ni aceptará
silenciosamente operaciones que no pueda cumplir.

D-Bus de sistema y de sesión son buses distintos. El bus de sesión será único por login gráfico y
compartido por compositor, DE, terminales y servicios activados por D-Bus. No se creará un bus
privado por perfil. El supervisor no suplanta `systemd1` ni anuncia compatibilidad parcial; solo
el proceso real puede poseer ese nombre.

Los portales serán servicios de sesión seleccionados por capacidad y escritorio: por ejemplo,
file chooser mediante Android Storage Access Framework, notificaciones mediante Android,
settings y screencast solo si pueden implementarse. `/dev/fuse` no se simulará: `xdg-document-portal`
debe desactivarse o sustituirse por una implementación que use las capacidades reales de la app.

### Sesión de escritorio

El contrato separa el perfil (`escritorio.conf`) del proveedor (`proveedores/<id>/proveedor.conf`).
El perfil declara el proveedor requerido, requisitos de sesión, capacidades necesarias, nivel de
readiness esperado, paquetes y ejecutable. El proveedor declara protocolo, entorno de conexión,
capacidades ofrecidas y el identificador/plazo de su comprobación de readiness. El supervisor
valida los requisitos y solo ejecuta comprobaciones que reconoce; una combinación no implementada
falla explícitamente.

El proveedor activo es `wayland-anidado`; todos los perfiles actuales lo declaran. Su comprobación
detecta un socket Wayland nuevo y publica el endpoint para TerminalService y los servicios. El host
consume el descriptor genérico de sesión y aplica el endpoint declarado al entorno de sus clientes;
los puentes específicos, como clipboard, se activan según el protocolo y las capacidades.
`READY_LEVEL=proveedor-y-proceso` no implica que el escritorio haya presentado un cuadro o que la
entrada, escala y portales funcionen. Añadir X11 requiere una comprobación propia y adaptar los
clientes que necesiten `DISPLAY`; el contrato no lo habilita por sí solo.

La disponibilidad debe distinguirse por capas: instalado, dependencias satisfechas, bus listo,
proveedor de pantalla listo, compositor/WM listo, portal listo y sesión interactiva. Un socket
presente no equivale a escritorio funcional.

## Wayland y X11

Wayland actual es un compositor anidado: el compositor Linux se conecta al socket de Wayland de
Android y publica el suyo para sus clientes. El camino GPU propio está ligado al wlroots parcheado;
un perfil basado en otro compositor puede arrancar por software o necesitar una integración propia.

Xwayland rootless sirve para ejecutar **aplicaciones X11** dentro de un compositor Wayland. En ese
modo el compositor Wayland hace de gestor X11 y no puede reemplazarse por un WM X11 convencional.
Por ello, no es por sí solo una sesión completa para XFCE/X11, Plasma/X11 u otro escritorio X11.
Referencia: [arquitectura oficial de Xwayland](https://wayland.freedesktop.org/docs/book/Xwayland.html).

La primera prueba de X11 será un proveedor **Xwayland rootful anidado** conectado como una ventana
Wayland a la superficie Android, y dentro de su root window se iniciará un WM y una sesión X11.
Hay que verificar que el Xwayland instalado pueda ejecutarse así sin que el compositor externo
reclame el WM X11, y que redimensionamiento, input, selección y salida funcionen. Si no es viable,
se evaluará un servidor X anidado como Xvnc con presentación integrada en Android; el coste de
copias y aceleración se medirá antes de elegirlo. No se tratará Xwayland rootless como sustituto.

El `Xorg` de escritorio directo no es el objetivo inicial: ese flujo suele requerir ser dueño de
DRM/KMS, VT e input del kernel, recursos que pertenecen a Android y no están expuestos a la app.

## Modelo de selección

La app mantendrá un registro de instalaciones, inicialmente:

| ID | Distribución | Estado |
|---|---|---|
| `arch-arm64` | Arch Linux ARM | Disponible; usa el prefijo existente `files/archlinux` y el instalador actual |
| `debian-arm64` | Debian arm64 | No disponible; requiere rootfs separado y adaptador |
| `ubuntu-arm64` | Ubuntu arm64 | No disponible; requiere rootfs separado y adaptador |

La app conserva una elección de sistema y otra de escritorio en la interfaz, pero resuelve y valida
la receta como combinación. La lista de escritorios debe mostrar cuáles tienen receta para el
sistema seleccionado. La terminal de rescate y los registros estarán asociados a una instalación
concreta. Hoy solo Arch tiene instalador.

## Fases de implementación (revisadas)

1. **Consolidar receta Arch + sway:** validar que selección, paquetes, overlay de configuración y
   arranque conservan el comportamiento conocido.
2. **Recetas Arch para otros escritorios:** una combinación por vez; capturar exactamente qué
   configuración y secuencia de procesos requiere (KDE primero por ser el fallo reproducible).
3. **Separar adaptadores de distribución:** añadir Debian y Ubuntu como rootfs independientes, con
   mapas de paquetes y configuraciones propios; no reutilizar nombres de paquetes de Arch.
4. **Mantener el supervisor común pequeño:** preparar entorno Android, iniciar el script declarado,
   descubrir el endpoint necesario para conectar los puentes y cerrar procesos. No requiere que
   cada DE siga un flujo Linux estándar.
5. **Proveedores gráficos:** ampliar solo cuando una receta necesite un protocolo distinto; no
   equiparar disponibilidad de socket con escritorio funcional.
   Los perfiles y proveedores declaran
   requisitos, capacidades y readiness. Pendiente: proveedores reales y adaptar clientes según
   pantalla antes de registrar otras distribuciones.
3. **Sesión estándar:** validar que el `systemd --user` iniciado desde la app puede operar sin
   system manager, logind ni cgroups delegados; resolver portales con servicios reales o adaptadores
   explícitos. KDE/Plasma Mobile exigen el user manager; no se declaran compatibles hasta validar
   sus readiness checks.
4. **Proveedor X11:** prototipo de Xwayland rootful anidado; comparar con Xvnc si no integra un WM
   X11 independiente. Mantener el modo Wayland y Xwayland rootless actual para apps X11.
5. **Registro multi-OS y selector (iniciado):** encapsular el Arch actual como primera instalación;
   el selector de Android ya muestra Arch disponible y Debian/Ubuntu inhabilitados. Añadir esas
   distribuciones solo después de que cada una tenga bootstrap, ABI, paquetes y sesión probados.
6. **Conformidad por perfil:** pruebas de servicios, imagen, input, resize/rotación, portales, X11,
   audio y cierre. Los errores se asignan a una capa, no se corrigen en el selector por excepción.

**37ª sesión (repo):** el selector de instalación Linux quedó como entrada del ícono. El registro
usa el ID `arch-arm64` y resuelve sus rutas al prefijo histórico; Debian y Ubuntu aparecen
deshabilitados hasta contar con rootfs y adaptador. La selección se conserva en preferencias y los
servicios consultan la raíz asociada. `sdk36Debug` compiló y esa APK se instaló después conservando
los datos; falta confirmar en el dispositivo el flujo del selector. Reinstalar una APK cierra la
sesión Linux activa.

**38ª sesión (repo):** el selector recibió una presentación tipo consola Linux: fuente monoespaciada,
prompt, paleta de terminal y etiquetas de estado. La compilación `sdk36Debug` se completó. La APK
anterior se había instalado; esta compilación con el rediseño sigue pendiente de instalación y
validación en el dispositivo.

**38ª sesión, continuación (repo):** `sesion-android` crea el bus D-Bus efímero y publica su
dirección para TerminalService; después del socket del compositor actualiza el entorno de activación
y lanza el supervisor de servicios. `autostart-android` conserva los PID de lo que inicia y al
cierre solicita apagar Steam por sway IPC antes de detener esos servicios. `dbus-run-session`
termina el bus cuando acaba el supervisor. KDE/Plasma Mobile dejan de crear un bus anidado. El bus
de sistema no se inicia porque ningún servicio actual lo necesita. La APK `sdk36Debug` y su capa
Linux ya se regeneraron; falta instalarla y validar arranque, terminales, notificaciones, audio y
cierre ordenado en el Redmi.

No se instalarán entornos en el teléfono como parte de estas fases sin revisar su tamaño y el
estado de la sesión; los prototipos de proveedor y gestor se validan primero aislados cuando sea
posible.
