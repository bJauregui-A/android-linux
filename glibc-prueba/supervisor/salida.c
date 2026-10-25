#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "common.h"
#include "salida.h"

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

void mostrar_logs(const char *name) {
    char path[512];
    rutaf(path, sizeof(path), "/var/log/supervisor/%s.log", name);
    FILE *f = fopen(path, "r");
    if (!f) {
        printf("\n   %sSin registros (%s)%s\n", MUTED, path, RESET);
        return;
    }

    printf("\n   %sÚltimos registros (%s.log):%s\n", BOLD, name, RESET);
    char lines[15][256];
    int count = 0;
    char buf[256];
    while (fgets(buf, sizeof(buf), f)) {
        size_t l = strlen(buf);
        if (l > 0 && buf[l - 1] == '\n') buf[l - 1] = '\0';
        strncpy(lines[count % 15], buf, sizeof(lines[0]) - 1);
        lines[count % 15][sizeof(lines[0]) - 1] = '\0';
        count++;
    }
    fclose(f);

    int start = (count > 15) ? (count - 15) : 0;
    for (int i = start; i < count; i++) {
        printf("     %s│%s %s\n", MUTED, RESET, lines[i % 15]);
    }
}

void mostrar_lista(char *resp) {
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

            int is_run = st && strcmp(st, "running") == 0;
            char upt_fmt[64];
            formatear_uptime(atol(upt_str ? upt_str : "0"), upt_fmt, sizeof(upt_fmt));

            const char *simbolo = is_run ? VERDE "●" RESET : MUTED "○" RESET;
            const char *st_col = is_run ? VERDE "running" RESET : MUTED "stopped" RESET;
            const char *enab_col = (enab && strcmp(enab, "1") == 0) ? VERDE "yes" RESET : MUTED "no" RESET;

            printf("%s    %-25s %-21s %-8s %-10s %-17s %s\n",
                   simbolo, nom, st_col, pid ? pid : "-", upt_fmt, enab_col, desc);
        }
        line = strtok(NULL, "\n");
    }
}

int mostrar_estado(char *resp) {
    if (strncmp(resp, "OK ", 3) != 0) return 0;
    resp[strcspn(resp, "\n")] = '\0';

    char *p = resp + 3;
    char *nom = strsep(&p, "|");
    char *st = strsep(&p, "|");
    char *pid = strsep(&p, "|");
    char *upt_str = strsep(&p, "|");
    char *restarts = strsep(&p, "|");
    char *enab = strsep(&p, "|");
    char *origen = strsep(&p, "|");
    char *desc = p ? p : nom;
    if (!st || !origen) return 0;

    int is_run = strcmp(st, "running") == 0;
    char upt_fmt[64];
    formatear_uptime(atol(upt_str ? upt_str : "0"), upt_fmt, sizeof(upt_fmt));

    printf("%s %s%s%s - %s\n",
           is_run ? VERDE "●" RESET : MUTED "○" RESET, BOLD, nom, RESET, desc);
    printf("     Loaded: %s (%s)\n", origen,
           (enab && strcmp(enab, "1") == 0) ? VERDE "enabled" RESET : MUTED "disabled" RESET);
    if (is_run) {
        printf("     Active: %sactive (running)%s (PID %s, activo hace %s)\n", VERDE, RESET, pid, upt_fmt);
    } else {
        printf("     Active: %sinactive (stopped)%s\n", MUTED, RESET);
    }
    if (restarts && atoi(restarts) > 0) {
        printf("   Restarts: %s%s veces%s\n", AMARILLO, restarts, RESET);
    }
    char log[512];
    rutaf(log, sizeof(log), "/var/log/supervisor/%s.log", nom);
    printf("       Logs: %s%s%s\n", MUTED, log, RESET);

    mostrar_logs(nom);
    return 1;
}

int mostrar_resultado(const char *resp) {
    if (strncmp(resp, "OK", 2) == 0) {
        printf("%s✔ %s%s", VERDE, resp + 3, RESET);
        return 0;
    }
    printf("%s✕ %s%s", ROJO, strncmp(resp, "ERR ", 4) == 0 ? resp + 4 : resp, RESET);
    return 1;
}
