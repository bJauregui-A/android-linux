#ifndef SALIDA_H
#define SALIDA_H

#define VERDE "\033[1;32m"
#define ROJO "\033[1;31m"
#define AMARILLO "\033[1;33m"
#define CIAN "\033[1;36m"
#define MUTED "\033[0;90m"
#define BOLD "\033[1m"
#define RESET "\033[0m"

// Tabla de la respuesta "SRV ..." del demonio (modifica resp).
void mostrar_lista(char *resp);

// Detalle de la respuesta "OK nombre|..." de status. 0 si resp no tiene ese formato.
int mostrar_estado(char *resp);

// OK/ERR genérico del demonio. Devuelve el código de salida.
int mostrar_resultado(const char *resp);

void mostrar_logs(const char *name);

#endif
