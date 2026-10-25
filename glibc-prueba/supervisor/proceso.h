#ifndef PROCESO_H
#define PROCESO_H

#include <sys/types.h>
#include <time.h>
#include "unidad.h"

typedef struct {
    Unidad u;
    pid_t pid;
    time_t start_time;
    int restart_count;
    int wanted_state; // 1 = debe estar corriendo, 0 = detenido a propósito
} Servicio;

// Devuelve el servicio registrado (cargándolo de disco si hace falta), o NULL.
Servicio *servicio_obtener(const char *nombre);

int servicio_corriendo(const Servicio *s);
long servicio_uptime(const Servicio *s);
int servicio_iniciar(Servicio *s);
void servicio_detener(Servicio *s);

// Recoge hijos terminados y reinicia los que deben seguir vivos.
void servicios_revisar_hijos(void);

int servicios_cantidad(void);
Servicio *servicio_en(int i);

#endif
