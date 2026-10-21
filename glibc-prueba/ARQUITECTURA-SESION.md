# Arquitectura de sistemas y sesiones gráficas

## Objetivo

Ofrecer dentro de la app un flujo de sesión Linux coherente para varias distribuciones ARM64 y
varios escritorios, sin convertir cada fallo de un entorno en una excepción aislada. La app seguirá
siendo un cliente sin root: Android conserva el control del hardware y el proyecto prepara el
espacio de usuario y los servicios que una sesión gráfica espera.

Distribución, escritorio y servidor gráfico son elecciones independientes:

```text
instalación Linux (Arch / Debian / Ubuntu)
    └── sesión (KDE / GNOME / XFCE / sway / ...)
          └── servidor gráfico (Wayland anidado / X11 anidado)
                └── superficie y entrada de Android
```

La selección inicial futura elige una **instalación Linux**. Dentro de ella, el usuario podrá
elegir un escritorio y el modo gráfico que ese escritorio soporte. No se debe guardar la
distribución elegida dentro del perfil del escritorio ni asumir que todo escritorio usa Wayland.

## Flujo de una sesión

El flujo objetivo, equivalente en sus contratos visibles a una sesión de escritorio, es:

1. Android inicia el servicio de la app y entrega una superficie, entrada, audio, almacenamiento
   y capacidades disponibles.
2. Un registro de instalaciones selecciona el rootfs y su adaptador de distribución. Se preparan
   usuario, grupos, `/tmp`, `/run/user/$UID`, `/dev`, `/proc`, `/sys` y las variables de entorno.
3. Se inicia el bus D-Bus de sistema cuando los servicios instalados lo necesiten y el gestor de
   servicios de usuario. Los servicios se inician con orden, readiness, registro y cierre
   supervisado.
4. Se crea un único bus D-Bus de sesión para esa sesión gráfica. Se publican en él las variables
   de pantalla/runtime antes de activar servicios D-Bus.
5. Se inicia el proveedor de pantalla seleccionado (Wayland o X11 anidado) y se espera su estado
   de listo, no solo que el proceso siga vivo.
6. Se inicia la sesión del escritorio con el entorno de pantalla, compositor, D-Bus, portales y
   servicios auxiliares ya definidos.
7. Al cerrar, se detiene el escritorio y luego los servicios de usuario en orden inverso. Android
   puede suspender la app; una reanudación debe reconectar a la misma instalación sin dejar
   sockets o procesos huérfanos.

El supervisor actual (`TerminalService` + `sesion-android`) ya cubre parcialmente los pasos 1, 5 y
7 para Wayland. D-Bus todavía se prepara por un script de perfil de shell. El primer cambio de
orquestación hace que `sesion-android` inicie los servicios comunes después de detectar el socket
para cualquier perfil; antes sway los iniciaba desde su configuración y los otros perfiles desde
el supervisor. El ciclo de vida y el cierre ordenado de esos servicios siguen pendientes.

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
con logs por unidad. Primero se evaluará si `systemd --user` puede funcionar sin privilegios de
Android y sin asumir cgroups delegados. Si una función requiere cgroups, namespaces, mounts o
acceso root, se declarará no disponible. Un supervisor alternativo puede iniciar procesos, pero no
se anunciará como `systemd1` completo ni aceptará silenciosamente operaciones que no pueda cumplir.

D-Bus de sistema y de sesión son buses distintos. El bus de sesión será único por login gráfico y
compartido por compositor, DE, terminales y servicios activados por D-Bus. No se creará un bus
privado por perfil. Los nombres estándar de servicios solo se expondrán cuando su comportamiento
esté implementado.

Los portales serán servicios de sesión seleccionados por capacidad y escritorio: por ejemplo,
file chooser mediante Android Storage Access Framework, notificaciones mediante Android,
settings y screencast solo si pueden implementarse. `/dev/fuse` no se simulará: `xdg-document-portal`
debe desactivarse o sustituirse por una implementación que use las capacidades reales de la app.

### Sesión de escritorio

Cada perfil declara metadatos, no una receta opaca: ID/nombre, paquetes, ejecutable de sesión,
protocolo requerido, variables, servicios y comprobaciones de readiness. Los perfiles pueden pedir
Wayland, X11 o ambos. El supervisor común resuelve dependencias, inicia el proveedor adecuado,
inyecta el entorno estándar (`XDG_RUNTIME_DIR`, `XDG_SESSION_TYPE`, `WAYLAND_DISPLAY` o
`DISPLAY`, D-Bus y rutas) y luego ejecuta la sesión.

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
| `arch-arm64` | Arch Linux ARM | Instalación existente; migración del selector sin reinstalar |
| `debian-arm64` | Debian arm64 | Futuro; rootfs separado |
| `ubuntu-arm64` | Ubuntu arm64 | Futuro; rootfs separado |

El inicio futuro tendrá dos decisiones independientes: **Sistema Linux** y **Escritorio/sesión**.
La segunda lista solo perfiles instalados y compatibles con las capacidades actuales. La terminal
de rescate y los registros estarán asociados a una instalación concreta.

## Fases de implementación

1. **Contrato y modelo (actual):** registrar capas, ciclo de vida, capacidades y límites; mantener
   Arch + sway como ruta funcional.
2. **Orquestador común (en curso):** todos los perfiles pasan por `sesion-android`, que descubre el
   socket y arranca los servicios comunes; quitar dependencias del config de sway. Siguiente:
   centralizar D-Bus/entorno y que el supervisor sea dueño del ciclo de vida de esos servicios.
   Después separar `TerminalService` de rutas Arch/sway y añadir logs por fase.
3. **Sesión estándar:** evaluar `systemd --user` bajo Android; resolver D-Bus de sistema/sesión y
   portales a través de servicios reales o adaptadores explícitos. No declarar Plasma compatible
   hasta cumplir sus readiness checks.
4. **Proveedor X11:** prototipo de Xwayland rootful anidado; comparar con Xvnc si no integra un WM
   X11 independiente. Mantener el modo Wayland y Xwayland rootless actual para apps X11.
5. **Registro multi-OS y selector:** encapsular el Arch actual como primera instalación; añadir
   Debian y Ubuntu solo después de que cada una tenga bootstrap, ABI, paquetes y sesión probados.
6. **Conformidad por perfil:** pruebas de servicios, imagen, input, resize/rotación, portales, X11,
   audio y cierre. Los errores se asignan a una capa, no se corrigen en el selector por excepción.

No se instalarán entornos en el teléfono como parte de estas fases sin revisar su tamaño y el
estado de la sesión; los prototipos de proveedor y gestor se validan primero aislados cuando sea
posible.
