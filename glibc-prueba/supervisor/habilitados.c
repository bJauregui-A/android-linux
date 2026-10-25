#define _GNU_SOURCE
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include "common.h"
#include "habilitados.h"

#define STATE_DIR "/var/lib/supervisor"
#define ENABLED_FILE STATE_DIR "/enabled.txt"

int habilitado_es(const char *nombre) {
    char ruta[512];
    rutaf(ruta, sizeof(ruta), "%s", ENABLED_FILE);
    FILE *f = fopen(ruta, "r");
    if (!f) return 0;
    char line[128];
    while (fgets(line, sizeof(line), f)) {
        trim(line);
        if (strcmp(line, nombre) == 0) {
            fclose(f);
            return 1;
        }
    }
    fclose(f);
    return 0;
}

static void actualizar_enlace(const Unidad *u, int enable) {
    char enlace[512];
    rutaf(enlace, sizeof(enlace), "%s/%s.service", DIR_SERVICIOS, u->nombre);
    if (enable) {
        if (!u->en_servicesd && access(enlace, F_OK) != 0) {
            char dir[512];
            rutaf(dir, sizeof(dir), "%s", DIR_SERVICIOS);
            mkdir(dir, 0755);
            symlink(u->origen, enlace);
        }
    } else {
        struct stat st;
        if (lstat(enlace, &st) == 0 && S_ISLNK(st.st_mode)) unlink(enlace);
    }
}

void habilitado_set(const Unidad *u, int enable) {
    actualizar_enlace(u, enable);

    char dir[512], ruta[512], tmp[560];
    rutaf(dir, sizeof(dir), "%s", STATE_DIR);
    rutaf(ruta, sizeof(ruta), "%s", ENABLED_FILE);
    mkdir(dir, 0755);
    snprintf(tmp, sizeof(tmp), "%s.tmp", ruta);

    FILE *f_in = fopen(ruta, "r");
    FILE *f_out = fopen(tmp, "w");
    if (!f_out) {
        if (f_in) fclose(f_in);
        return;
    }

    int ya_estaba = 0;
    char line[128];
    if (f_in) {
        while (fgets(line, sizeof(line), f_in)) {
            trim(line);
            if (strcmp(line, u->nombre) == 0) {
                if (enable) {
                    fprintf(f_out, "%s\n", u->nombre);
                    ya_estaba = 1;
                }
            } else if (line[0] != '\0') {
                fprintf(f_out, "%s\n", line);
            }
        }
        fclose(f_in);
    }
    if (enable && !ya_estaba) fprintf(f_out, "%s\n", u->nombre);
    fclose(f_out);
    rename(tmp, ruta);
}

void habilitados_cada(void (*cb)(const char *nombre, void *ctx), void *ctx) {
    char ruta[512];
    rutaf(ruta, sizeof(ruta), "%s", ENABLED_FILE);
    FILE *f = fopen(ruta, "r");
    if (!f) return;
    char line[128];
    while (fgets(line, sizeof(line), f)) {
        trim(line);
        if (line[0] != '\0') cb(line, ctx);
    }
    fclose(f);
}
