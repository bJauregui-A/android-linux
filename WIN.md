# WIN.md — Arquitectura de Compatibilidad Nativa con Windows en Linux ARM64

Documento de visión, diseño y hoja de ruta para la compatibilidad nativa con aplicaciones y juegos de Windows en Linux (Arch ARM64 sin root, sobre Android/Wayland).

---

## 1. Visión y Filosofía: Traducción Semántica Directa

El objetivo no es clonar la maquinaria interna de Windows ni recrear toda la burocracia histórica del sistema operativo (servidores centrales, registro masivo de Windows, subsistema de objetos NT complejo o capas de emulación pesadas).

La filosofía se basa en **cumplir la interfaz externa** que los ejecutables esperan (firmas de funciones, estructuras y contratos de la API Win32/DirectX), pero **resolviendo todo internamente con los primitivos más eficientes y veloces que ofrece Linux nativamente**:

- **Sin máquinas virtuales ni emulación de hardware**: El código se ejecuta directamente en la CPU y en la GPU Adreno física vía Vulkan.
- **Sin capas intermedias innecesarias**: Si una llamada de Windows se puede resolver con una syscall directa de Linux (`futex`, `mmap`, `epoll`), se conecta de inmediato sin pasar por intermediarios.
- **Cero copias gráficas**: El renderizado debe fluir directo desde DirectX (vía DXVK/Vulkan) a la pantalla mediante superficies Wayland y buffers de memoria compartida (`dmabuf` / `AHardwareBuffer`).

---

## 2. Windows on ARM y Componentes Oficiales de Microsoft

### Qué es y cómo opera Windows on ARM (WoA)
Windows on ARM corre sobre un núcleo NT nativo en ARM64 (`aarch64`). Para compatibilidad hacia atrás utiliza:
1. **ARM64 Nativo**: Binarios compilados directo para la arquitectura.
2. **ARM64EC (*Emulation Compatible*)**: ABI híbrida que permite mezclar código ARM64 nativo y DLLs x64 en el mismo proceso.
3. **Prism / WOW64**: Motor de traducción de instrucciones x86/x64 a ARM64.

### Qué binarios de Microsoft se pueden aprovechar directamente
- **Runtimes de C/C++ Oficiales (ARM64)**: Los paquetes `vc_redist.arm64.exe` instalan DLLs oficiales nativas (`msvcp140.dll`, `vcruntime140.dll`, etc.) que pueden usarse en el prefijo para reemplazar stubs.
- **DirectX Shader Compiler y D3DCompiler**: Compilaciones oficiales ARM64 de `d3dcompiler_47.dll` y `dxcompiler.dll` (DirectX Agility SDK) para procesamiento óptimo de shaders.
- **.NET Desktop Runtime (ARM64)**: Entorno nativo para juegos y lanzadores modernos basados en C# / .NET.
- **La especificación ARM64EC**: Base que permite a herramientas como Proton ARM64 y FEX saltar de código emulado x86/x64 directo a bibliotecas nativas de Linux en tiempo cero.

*Nota técnica:* El emulador de Microsoft (Prism / `xtajit.dll`) depende íntimamente del kernel NT propietario; en Linux, **FEX-Emu** proporciona la traducción de instrucciones x86/x64 integrada limpiamente con el ecosistema abierto.

---

## 3. Mapeo Arquitectónico: Windows → Linux Nativo

| Componente | Mecanismo tradicional de Windows / Wine clásico | Implementación Nativa Óptima en Linux | Beneficio |
|---|---|---|---|
| **Sincronización** (`WaitForSingleObject`, `CreateEvent`, `Mutex`) | Peticiones IPC constantes por socket Unix a `wineserver` | **`futex` del kernel Linux (`WINEFSYNC=1` / `ntsync`)** | Sincronización a velocidad de hardware; elimina saturación de CPU en juegos multihilo. |
| **Ventanas y Presentación** (`HWND`, creación de ventanas) | `winex11.drv` → Sockets X11 → Xwayland → Sway | **`winewayland.drv` directo a `wl_surface`** | Elimina X11 y Xwayland del camino; la ventana es una superficie Wayland pura. |
| **Gráficos 3D** (Direct3D 9 / 11 / 12) | Capas de compatibilidad D3D o emulación CPU | **DXVK / VKD3D → Vulkan nativo (Turnip Adreno 619)** | Los comandos de dibujo entran directo a la GPU física sin copias intermedias. |
| **Memoria Virtual** (`VirtualAlloc`, `VirtualProtect`) | Gestor de memoria simulado en heap | **`mmap(MAP_ANONYMOUS)` y `mprotect` directos** | Gestión de páginas delegada 100% al MMU de Linux. |
| **Descriptores / Objetos** (`HANDLE`) | Tabla global de objetos con seguridad NT | **File Descriptors (`fd`) con `epoll` / `eventfd`** | Manejo unificado de I/O y eventos sin burocracia interna. |
| **Audio** (DirectSound, XAudio2) | Emulación de drivers de audio Windows | **Stream directo a PipeWire / FIFO AudioTrack** | Baja latencia (48 kHz) y sin intermediarios. |

---

## 4. Hoja de Ruta de Implementación en este Proyecto

### Fase 1: Optimización Inmediata de Rendimiento (Sincronización y GL)
- [ ] **Activar `WINEFSYNC=1` por defecto** en `steam/proton-directo/proton` y Lutris.
  - Verificar soporte de futex en el kernel del teléfono (ya validado en la sesión 14ª).
  - Aliviar el hilo principal de emuladores y motores como Unity (ej. ATLYSS).
- [ ] **Generalizar `~/mesa-gl` en `proton-directo`**:
  - Habilitar aceleración OpenGL por GPU en juegos que corran sobre WineD3D (como Morrowind), eliminando el renderizado por software (llvmpipe).

### Fase 2: Camino Gráfico Directo (`winewayland`)
- [ ] **Integrar el driver `winewayland` en Proton/Wine ARM64**:
  - Compilar `winewayland.drv` / `winewayland.so` con el toolchain ARM64/ARM64EC.
  - Configurar las variables de entorno para que los juegos seleccionen el backend de Wayland en vez de X11 (`DISPLAY`).
  - Obtener renderizado de Cero Copias real: Vulkan WSI presentando directo en AHardwareBuffers/dmabufs de sway.

### Fase 3: Entrada y Periféricos
- [ ] **Mapeo directo de entrada táctil y cursor**:
  - Resolver el problema de movimiento relativo en DirectInput (caso Morrowind) mediante warp de cursor o conversión directa de eventos Wayland.
- [ ] **Audio nativo sin retraso**:
  - Mantener la ruta de PipeWire hacia el FIFO de Android (`/tmp/audio-android`) optimizada para hilos de audio de Proton.

### Fase 4: Runtime Win32 Minimalista (Largo Plazo)
- [ ] Investigar la viabilidad de un cargador de binarios Win32 PE ligero (estilo Winelib o cargador directo C++) que enlace las funciones requeridas de un ejecutable contra Wayland y Vulkan sin requerir la infraestructura de un prefijo completo de Windows cuando no sea necesario.
