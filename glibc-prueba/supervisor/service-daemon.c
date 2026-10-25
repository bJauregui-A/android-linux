#define _GNU_SOURCE
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>
#include "common.h"
#include "habilitados.h"
#include "proceso.h"

static volatile sig_atomic_t g_running = 1;

typedef void (*Manejador)(const char *arg, char *resp, size_t n);

// Busca el servicio o deja en resp el error que se enviará al cliente.
static Servicio *requerir(const char *arg, char *resp, size_t n) {
    if (arg[0] == '\0') {
        snprintf(resp, n, "ERR Falta el nombre del servicio\n");
        return NULL;
    }
    Servicio *s = servicio_obtener(arg);
    if (!s) {
        char dirs[512];
        unidad_dirs_texto(dirs, sizeof(dirs));
        snprintf(resp, n, "ERR Servicio '%s' no encontrado (buscado en %s)\n", arg, dirs);
    }
    return s;
}

static void cmd_ping(const char *arg, char *resp, size_t n) {
    (void)arg;
    snprintf(resp, n, "PONG\n");
}

static void cmd_start(const char *arg, char *resp, size_t n) {
    Servicio *s = requerir(arg, resp, n);
    if (!s) return;
    if (servicio_iniciar(s) == 0) snprintf(resp, n, "OK Servicio %s iniciado (PID %d)\n", s->u.nombre, s->pid);
    else snprintf(resp, n, "ERR Fallo al iniciar %s\n", s->u.nombre);
}

static void cmd_stop(const char *arg, char *resp, size_t n) {
    Servicio *s = requerir(arg, resp, n);
    if (!s) return;
    servicio_detener(s);
    snprintf(resp, n, "OK Servicio %s detenido\n", s->u.nombre);
}

static void cmd_restart(const char *arg, char *resp, size_t n) {
    Servicio *s = requerir(arg, resp, n);
    if (!s) return;
    servicio_detener(s);
    usleep(200000);
    servicio_iniciar(s);
    snprintf(resp, n, "OK Servicio %s reiniciado (PID %d)\n", s->u.nombre, s->pid);
}

static void cmd_enable(const char *arg, char *resp, size_t n) {
    Servicio *s = requerir(arg, resp, n);
    if (!s) return;
    habilitado_set(&s->u, 1);
    servicio_iniciar(s);
    snprintf(resp, n, "OK Servicio %s habilitado para auto-arranque\n", s->u.nombre);
}

static void cmd_disable(const char *arg, char *resp, size_t n) {
    Servicio *s = requerir(arg, resp, n);
    if (!s) return;
    habilitado_set(&s->u, 0);
    snprintf(resp, n, "OK Servicio %s deshabilitado\n", s->u.nombre);
}

static void cmd_status(const char *arg, char *resp, size_t n) {
    Servicio *s = requerir(arg, resp, n);
    if (!s) return;
    int running = servicio_corriendo(s);
    snprintf(resp, n, "OK %s|%s|%d|%ld|%d|%d|%s|%s\n",
             s->u.nombre, running ? "running" : "stopped", running ? s->pid : 0,
             servicio_uptime(s), s->restart_count, habilitado_es(s->u.nombre),
             s->u.origen, s->u.descripcion);
}

static void cargar_unidad(const char *nombre, void *ctx) {
    (void)ctx;
    servicio_obtener(nombre);
}

static void cmd_list(const char *arg, char *resp, size_t n) {
    int todo = (strcasecmp(arg, "ALL") == 0 || strcasecmp(arg, "-a") == 0);
    unidad_listar(todo, cargar_unidad, NULL);

    size_t off = 0;
    for (int i = 0; i < servicios_cantidad() && off < n - 256; i++) {
        Servicio *s = servicio_en(i);
        int running = servicio_corriendo(s);
        int enab = habilitado_es(s->u.nombre);
        // Listado estándar: solo lo definido en services.d, habilitado o activo.
        if (!todo && !running && !enab && !s->u.en_servicesd) continue;
        off += snprintf(resp + off, n - off, "SRV %s|%s|%d|%ld|%d|%s\n",
                        s->u.nombre, running ? "running" : "stopped", running ? s->pid : 0,
                        servicio_uptime(s), enab, s->u.descripcion);
    }
    snprintf(resp + off, n - off, "END\n");
}

static const struct { const char *nombre; Manejador f; } COMANDOS[] = {
    {"PING", cmd_ping}, {"START", cmd_start}, {"STOP", cmd_stop}, {"RESTART", cmd_restart},
    {"ENABLE", cmd_enable}, {"DISABLE", cmd_disable}, {"STATUS", cmd_status}, {"LIST", cmd_list},
    {NULL, NULL}
};

static void manejar_cliente(int client_fd) {
    char req[512];
    ssize_t n = read(client_fd, req, sizeof(req) - 1);
    if (n <= 0) {
        close(client_fd);
        return;
    }
    req[n] = '\0';
    trim(req);

    char cmd[64] = {0};
    char arg[128] = {0};
    sscanf(req, "%63s %127s", cmd, arg);

    static char resp[65536];
    memset(resp, 0, sizeof(resp));

    int hecho = 0;
    for (int i = 0; COMANDOS[i].nombre; i++) {
        if (strcasecmp(cmd, COMANDOS[i].nombre) == 0) {
            COMANDOS[i].f(arg, resp, sizeof(resp));
            hecho = 1;
            break;
        }
    }
    if (!hecho) snprintf(resp, sizeof(resp), "ERR Comando desconocido\n");

    write(client_fd, resp, strlen(resp));
    close(client_fd);
}

static void iniciar_habilitado(const char *nombre, void *ctx) {
    (void)ctx;
    Servicio *s = servicio_obtener(nombre);
    if (s) servicio_iniciar(s);
}

int main(void) {
    signal(SIGPIPE, SIG_IGN);

    char sock_path[256];
    ruta_socket(sock_path, sizeof(sock_path));
    unlink(sock_path);

    int sfd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (sfd < 0) {
        perror("socket");
        return 1;
    }

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, sock_path, sizeof(addr.sun_path) - 1);

    if (bind(sfd, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        perror("bind");
        close(sfd);
        return 1;
    }
    chmod(sock_path, 0777);

    if (listen(sfd, 16) != 0) {
        perror("listen");
        close(sfd);
        return 1;
    }

    habilitados_cada(iniciar_habilitado, NULL);

    int flags = fcntl(sfd, F_GETFL, 0);
    fcntl(sfd, F_SETFL, flags | O_NONBLOCK);

    while (g_running) {
        servicios_revisar_hijos();

        int cfd = accept(sfd, NULL, NULL);
        if (cfd >= 0) manejar_cliente(cfd);
        else usleep(100000);
    }

    close(sfd);
    unlink(sock_path);
    return 0;
}
