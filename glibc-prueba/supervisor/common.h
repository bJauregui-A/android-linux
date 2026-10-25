#ifndef COMMON_H
#define COMMON_H

#include <stddef.h>

// Quita espacios/tabs/saltos al final y espacios/tabs al inicio, en sitio.
void trim(char *s);

// Ruta del socket del supervisor (XDG_RUNTIME_DIR, $GLIBC_PREFIX/run, /run o /tmp).
void ruta_socket(char *out, size_t maxlen);

// snprintf de una ruta del sistema de archivos del supervisor. Si existe SERVICE_ROOT
// se antepone (solo para probar en el PC sin tocar /etc ni /var).
void rutaf(char *out, size_t maxlen, const char *fmt, ...) __attribute__((format(printf, 3, 4)));

#endif
