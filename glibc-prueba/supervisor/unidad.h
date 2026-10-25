#ifndef UNIDAD_H
#define UNIDAD_H

#include <stddef.h>

#define DIR_SERVICIOS "/etc/services.d"
#define CMD_MAX 1024

typedef struct {
    char nombre[64];        // canónico: nombre del archivo real sin .service/.conf
    char origen[512];       // archivo de unidad que se leyó
    char descripcion[128];
    char exec_pre[CMD_MAX]; // ExecStartPre encadenados con &&
    char exec_start[CMD_MAX];
    char exec_stop[CMD_MAX];
    char working_dir[256];
    char env_file[256];
    char runtime_dir[64];
    int restart_always;
    int en_servicesd;       // la unidad está definida (o enlazada) en /etc/services.d
} Unidad;

// Busca y parsea la unidad. Acepta alias comunes (sshd, ssh, openssh-server...).
// Devuelve 0 si se cargó, -1 si no existe o no tiene ExecStart.
int unidad_cargar(const char *nombre, Unidad *u);

// Llama cb con el nombre de cada unidad de /etc/services.d (y, con incluir_sistema,
// también las de systemd).
void unidad_listar(int incluir_sistema, void (*cb)(const char *nombre, void *ctx), void *ctx);

// Texto con los directorios donde se busca, para mensajes de error.
void unidad_dirs_texto(char *out, size_t maxlen);

#endif
