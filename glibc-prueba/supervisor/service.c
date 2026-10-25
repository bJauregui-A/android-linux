#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include "cliente.h"
#include "salida.h"

static const char *const ACCIONES[] = {"start", "stop", "restart", "status", "enable", "disable", "logs", NULL};

static int es_accion(const char *s) {
    for (int i = 0; ACCIONES[i]; i++) {
        if (strcmp(s, ACCIONES[i]) == 0) return 1;
    }
    return 0;
}

static void uso(void) {
    printf("%sUso:%s service <acción> <nombre>\n", BOLD, RESET);
    printf("     service list [-a] | service status\n\n");
    printf("%sAcciones:%s\n", BOLD, RESET);
    printf("  %sstart%s    Inicia el servicio en segundo plano\n", CIAN, RESET);
    printf("  %sstop%s     Detiene el servicio limpiamente\n", CIAN, RESET);
    printf("  %srestart%s  Reinicia el servicio\n", CIAN, RESET);
    printf("  %sstatus%s   Muestra estado en vivo, PID, uptime y logs\n", CIAN, RESET);
    printf("  %senable%s   Habilita el auto-arranque del servicio\n", CIAN, RESET);
    printf("  %sdisable%s  Deshabilita el auto-arranque\n", CIAN, RESET);
    printf("  %slogs%s     Muestra los últimos logs del servicio\n", CIAN, RESET);
    printf("  %slist%s     Lista los servicios configurados y activos (-a: todas las unidades systemd)\n", CIAN, RESET);
    exit(1);
}

int main(int argc, char **argv) {
    const char *accion = NULL;
    const char *nombre = NULL;

    if (argc < 2) uso();

    if (strcmp(argv[1], "list") == 0) {
        accion = "list";
        if (argc >= 3) nombre = argv[2];
    } else if (argc == 2 && strcmp(argv[1], "status") == 0) {
        accion = "list";
    } else if (es_accion(argv[1])) {
        if (argc < 3) {
            fprintf(stderr, "%sFalta el nombre del servicio: service %s <nombre>%s\n", ROJO, argv[1], RESET);
            return 1;
        }
        accion = argv[1];
        nombre = argv[2];
    } else {
        fprintf(stderr, "%sAcción desconocida: '%s'%s\n\n", ROJO, argv[1], RESET);
        uso();
    }

    char req[512];
    if (strcmp(accion, "list") == 0) {
        int todo = nombre && (strcmp(nombre, "-a") == 0 || strcasecmp(nombre, "all") == 0);
        snprintf(req, sizeof(req), todo ? "LIST ALL\n" : "LIST\n");
    } else {
        // logs no es un comando del demonio: se pide status para obtener el nombre canónico
        snprintf(req, sizeof(req), "%s %s\n", strcmp(accion, "logs") == 0 ? "status" : accion, nombre);
    }

    static char resp[65536];
    long total = pedir_al_demonio(req, resp, sizeof(resp));
    if (total < 0) {
        fprintf(stderr, "%sError: No se pudo conectar al demonio supervisor%s\n", ROJO, RESET);
        return 1;
    }
    if (total == 0) {
        fprintf(stderr, "%sError: Respuesta vacía del supervisor%s\n", ROJO, RESET);
        return 1;
    }

    if (strcmp(accion, "list") == 0) {
        mostrar_lista(resp);
        return 0;
    }
    if (strcmp(accion, "status") == 0 && mostrar_estado(resp)) return 0;
    if (strcmp(accion, "logs") == 0 && strncmp(resp, "OK ", 3) == 0) {
        // logs: el nombre canónico viene en la respuesta de status
        char *p = resp + 3;
        char *nom = strsep(&p, "|");
        mostrar_logs(nom);
        return 0;
    }
    return mostrar_resultado(resp);
}
