#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <time.h>

#define VERDE "\033[1;32m"
#define ROJO "\033[1;31m"
#define AMARILLO "\033[1;33m"
#define CIAN "\033[1;36m"
#define MUTED "\033[0;90m"
#define BOLD "\033[1m"
#define RESET "\033[0m"

static void obtener_socket_path(char *out, size_t maxlen) {
    const char *x = getenv("XDG_RUNTIME_DIR");
    if (x && access(x, W_OK) == 0) {
        snprintf(out, maxlen, "%s/supervisor.sock", x);
        return;
    }
    const char *p = getenv("GLIBC_PREFIX");
    if (p) {
        char buf[512];
        snprintf(buf, sizeof(buf), "%s/run", p);
        if (access(buf, W_OK) == 0) {
            snprintf(out, maxlen, "%s/supervisor.sock", buf);
            return;
        }
    }
    if (access("/run", W_OK) == 0) {
        snprintf(out, maxlen, "/run/supervisor.sock");
        return;
    }
    snprintf(out, maxlen, "/tmp/supervisor.sock");
}

static int conectar_demonio(void) {
    char sock_path[256];
    obtener_socket_path(sock_path, sizeof(sock_path));

    for (int intento = 0; intento < 2; intento++) {
        int fd = socket(AF_UNIX, SOCK_STREAM, 0);
        if (fd < 0) return -1;

        struct sockaddr_un addr;
        memset(&addr, 0, sizeof(addr));
        addr.sun_family = AF_UNIX;
        strncpy(addr.sun_path, sock_path, sizeof(addr.sun_path) - 1);

        if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) == 0) {
            return fd;
        }
        close(fd);

        if (intento == 0) {
            // Lanzar el demonio si no estaba corriendo
            if (fork() == 0) {
                close(0); close(1); close(2);
                execl("/usr/local/bin/service-daemon", "service-daemon", (char *)NULL);
                exit(1);
            }
            usleep(250000); // 250ms
        }
    }
    return -1;
}

static void formatear_uptime(long segs, char *out, size_t maxlen) {
    if (segs <= 0) {
        snprintf(out, maxlen, "-");
        return;
    }
    long m = segs / 60;
    long s = segs % 60;
    long h = m / 60;
    m %= 60;
    long d = h / 24;
    h %= 24;

    if (d > 0) snprintf(out, maxlen, "%ldd %ldh %ldm", d, h, m);
    else if (h > 0) snprintf(out, maxlen, "%ldh %ldm %lds", h, m, s);
    else if (m > 0) snprintf(out, maxlen, "%ldm %lds", m, s);
    else snprintf(out, maxlen, "%lds", s);
}

static void mostrar_logs(const char *name) {
    char path[512];
    snprintf(path, sizeof(path), "/var/log/supervisor/%s.log", name);
    FILE *f = fopen(path, "r");
    if (!f) return;

    printf("\n   %sÚltimos registros (%s.log):%s\n", BOLD, name, RESET);
    char lines[15][256];
    int count = 0;
    char buf[256];
    while (fgets(buf, sizeof(buf), f)) {
        size_t l = strlen(buf);
        if (l > 0 && buf[l - 1] == '\n') buf[l - 1] = '\0';
        strncpy(lines[count % 15], buf, sizeof(lines[0]) - 1);
        count++;
    }
    fclose(f);

    int start = (count > 15) ? (count - 15) : 0;
    for (int i = start; i < count; i++) {
        printf("     %s│%s %s\n", MUTED, RESET, lines[i % 15]);
    }
}

static void uso(void) {
    printf("%sUso:%s service <nombre> <start|stop|restart|status|enable|disable|logs>\n", BOLD, RESET);
    printf("     service list [-a] | service status\n\n");
    printf("%sComandos:%s\n", BOLD, RESET);
    printf("  %sstart%s    Inicia el servicio en segundo plano\n", CIAN, RESET);
    printf("  %sstop%s     Detiene el servicio limpiamente\n", CIAN, RESET);
    printf("  %srestart%s  Reinicia el servicio\n", CIAN, RESET);
    printf("  %sstatus%s   Muestra estado en vivo, PID, uptime y logs\n", CIAN, RESET);
    printf("  %senable%s   Habilita el auto-arranque del servicio\n", CIAN, RESET);
    printf("  %sdisable%s  Deshabilita el auto-arranque\n", CIAN, RESET);
    printf("  %slogs%s     Muestra los últimos logs del servicio\n", CIAN, RESET);
    printf("  %slist%s     Lista los servicios configurados y activos (usar -a para ver todas las unidades systemd)\n", CIAN, RESET);
    exit(1);
}

int main(int argc, char **argv) {
    if (argc < 2) uso();

    const char *nombre = NULL;
    const char *accion = NULL;

    if (strcmp(argv[1], "list") == 0) {
        accion = "list";
        if (argc >= 3) nombre = argv[2];
    } else if (argc == 2) {
        if (strcmp(argv[1], "status") == 0) {
            accion = "list";
        } else {
            nombre = argv[1];
            accion = "status";
        }
    } else {
        const char *a1 = argv[1];
        const char *a2 = argv[2];
        const char *validos[] = {"start", "stop", "restart", "status", "enable", "disable", "logs", NULL};
        int es_valido_a2 = 0, es_valido_a1 = 0;
        for (int i = 0; validos[i]; i++) {
            if (strcmp(a2, validos[i]) == 0) es_valido_a2 = 1;
            if (strcmp(a1, validos[i]) == 0) es_valido_a1 = 1;
        }

        if (es_valido_a2) {
            nombre = a1; accion = a2;
        } else if (es_valido_a1) {
            accion = a1; nombre = a2;
        } else {
            uso();
        }
    }

    int sfd = conectar_demonio();
    if (sfd < 0) {
        fprintf(stderr, "%sError: No se pudo conectar al demonio supervisor en /run/supervisor.sock%s\n", ROJO, RESET);
        return 1;
    }

    char req[512];
    if (strcmp(accion, "list") == 0) {
        if (nombre && (strcmp(nombre, "-a") == 0 || strcasecmp(nombre, "all") == 0)) {
            snprintf(req, sizeof(req), "LIST ALL\n");
        } else {
            snprintf(req, sizeof(req), "LIST\n");
        }
    } else {
        snprintf(req, sizeof(req), "%s %s\n", accion, nombre);
    }
    write(sfd, req, strlen(req));

    static char resp[65536];
    size_t total = 0;
    while (total < sizeof(resp) - 1) {
        ssize_t n = read(sfd, resp + total, sizeof(resp) - 1 - total);
        if (n <= 0) break;
        total += n;
    }
    close(sfd);

    if (total == 0) {
        fprintf(stderr, "%sError: Respuesta vacía del supervisor%s\n", ROJO, RESET);
        return 1;
    }
    resp[total] = '\0';

    if (strcmp(accion, "list") == 0) {
        printf("%s%-4s %-25s %-12s %-8s %-10s %-8s %s%s\n",
               BOLD, "EST", "SERVICIO", "ESTADO", "PID", "UPTIME", "AUTO", "DESCRIPCIÓN", RESET);
        printf("%s%s%s\n", MUTED, "-------------------------------------------------------------------------------------", RESET);

        char *line = strtok(resp, "\n");
        while (line) {
            if (strncmp(line, "SRV ", 4) == 0) {
                char *p = line + 4;
                char *nom = strsep(&p, "|");
                char *st = strsep(&p, "|");
                char *pid = strsep(&p, "|");
                char *upt_str = strsep(&p, "|");
                char *enab = strsep(&p, "|");
                char *desc = p ? p : nom;

                int is_run = (strcmp(st, "running") == 0);
                long uptime_val = atol(upt_str ? upt_str : "0");
                char upt_fmt[64];
                formatear_uptime(uptime_val, upt_fmt, sizeof(upt_fmt));

                const char *simbolo = is_run ? VERDE "●" RESET : MUTED "○" RESET;
                const char *st_col = is_run ? VERDE "running" RESET : MUTED "stopped" RESET;
                const char *enab_col = (enab && strcmp(enab, "1") == 0) ? VERDE "yes" RESET : MUTED "no" RESET;

                printf("%s    %-25s %-21s %-8s %-10s %-17s %s\n",
                       simbolo, nom, st_col, pid ? pid : "-", upt_fmt, enab_col, desc);
            }
            line = strtok(NULL, "\n");
        }
        return 0;
    }

    if (strcmp(accion, "status") == 0) {
        if (strncmp(resp, "OK ", 3) == 0) {
            char *p = resp + 3;
            char *nom = strsep(&p, "|");
            char *st = strsep(&p, "|");
            char *pid = strsep(&p, "|");
            char *upt_str = strsep(&p, "|");
            char *restarts = strsep(&p, "|");
            char *enab = strsep(&p, "|");
            char *desc = p ? p : nom;

            int is_run = (strcmp(st, "running") == 0);
            long uptime_val = atol(upt_str ? upt_str : "0");
            char upt_fmt[64];
            formatear_uptime(uptime_val, upt_fmt, sizeof(upt_fmt));

            printf("%s %s%s%s - %s\n",
                   is_run ? VERDE "●" RESET : MUTED "○" RESET,
                   BOLD, nom, RESET, desc);
            printf("     Loaded: /etc/services.d/%s (%s)\n", nom,
                   (enab && strcmp(enab, "1") == 0) ? VERDE "enabled" RESET : MUTED "disabled" RESET);
            if (is_run) {
                printf("     Active: %sactive (running)%s (PID %s, activo hace %s)\n", VERDE, RESET, pid, upt_fmt);
            } else {
                printf("     Active: %sinactive (stopped)%s\n", MUTED, RESET);
            }
            if (restarts && atoi(restarts) > 0) {
                printf("   Restarts: %s%s veces%s\n", AMARILLO, restarts, RESET);
            }
            printf("       Logs: %s/var/log/supervisor/%s.log%s\n", MUTED, nom, RESET);

            mostrar_logs(nom);
            return 0;
        }
    }

    if (strncmp(resp, "OK", 2) == 0) {
        printf("%s✔ %s%s", VERDE, resp + 3, RESET);
    } else {
        printf("%s✕ %s%s", ROJO, resp + 4, RESET);
        return 1;
    }

    return 0;
}
