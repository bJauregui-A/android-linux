cmake_minimum_required(VERSION 3.22)
project(anfitrion C)

# libwayland-server y libffi estáticas para Android: wayland/compilar.sh
set(WL ${CMAKE_CURRENT_SOURCE_DIR}/../../../../wayland/salida)

add_library(anfitrion SHARED anfitrion.c ${WL}/proto/xdg-shell-protocol.c ${WL}/proto/linux-dmabuf-v1-protocol.c ${WL}/proto/android-ahb-v1-protocol.c ${WL}/proto/pointer-gestures-unstable-v1-protocol.c)
# Funciones de API 31 (ASurfaceControl) como símbolos débiles: Android 11 usa la copia por CPU.
target_compile_definitions(anfitrion PRIVATE __ANDROID_UNAVAILABLE_SYMBOLS_ARE_WEAK__)
target_include_directories(anfitrion PRIVATE ${WL}/include ${WL}/proto)
target_link_libraries(anfitrion ${WL}/lib/libwayland-server.a ${WL}/lib/libffi.a android log m)
