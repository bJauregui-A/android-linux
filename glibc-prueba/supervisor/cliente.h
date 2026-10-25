#ifndef CLIENTE_H
#define CLIENTE_H

#include <stddef.h>

// Conecta con el demonio (lo lanza si no corría). -1 si no se pudo.
int conectar_demonio(void);

// Envía req y lee la respuesta completa en resp. Devuelve los bytes leídos, o -1 sin demonio.
long pedir_al_demonio(const char *req, char *resp, size_t maxlen);

#endif
