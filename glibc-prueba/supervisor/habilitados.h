#ifndef HABILITADOS_H
#define HABILITADOS_H

#include "unidad.h"

int habilitado_es(const char *nombre);

// Marca/desmarca el auto-arranque. Al habilitar una unidad de systemd la enlaza en
// /etc/services.d; al deshabilitar solo quita enlaces, nunca archivos propios del usuario.
void habilitado_set(const Unidad *u, int enable);

void habilitados_cada(void (*cb)(const char *nombre, void *ctx), void *ctx);

#endif
