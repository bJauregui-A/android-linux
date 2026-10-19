cmake_minimum_required(VERSION 3.22)
project(anfitrion C)

# libwayland-server y libffi estáticas para Android: wayland/compilar.sh
set(WL ${CMAKE_CURRENT_SOURCE_DIR}/../../../../wayland/salida)

add_library(anfitrion SHARED anfitrion.c ${WL}/proto/xdg-shell-protocol.c ${WL}/proto/linux-dmabuf-v1-protocol.c)
target_include_directories(anfitrion PRIVATE ${WL}/include ${WL}/proto)
target_link_libraries(anfitrion ${WL}/lib/libwayland-server.a ${WL}/lib/libffi.a android log m)
