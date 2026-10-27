#define _GNU_SOURCE
#include <dirent.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>
#include <unistd.h>
#include "common.h"
#include "unidad.h"

// Arch usa /usr/lib; Debian sin usr-merge deja las unidades de paquetes en /lib.
static const char *const DIRS_SISTEMA[] = {
    "/etc/systemd/system", "/usr/lib/systemd/system", "/lib/systemd/system", NULL
};

// El nombre del paquete o de la unidad cambia entre distros.
static const struct { const char *nombre, *alias; } ALIAS[] = {
    {"sshd", "ssh"}, {"ssh", "sshd"}, {"openssh-server", "ssh"}, {"openssh", "sshd"},
    {"apache2", "httpd"}, {"httpd", "apache2"}, {NULL, NULL}
};

static int es_archivo(const char *ruta) {
    struct stat st;
    return stat(ruta, &st) == 0 && S_ISREG(st.st_mode) && access(ruta, R_OK) == 0;
}

static int buscar_en_dir(const char *dir, const char *nombre, char *out, size_t n) {
    static const char *const sufijos[] = {"", ".service", ".conf", NULL};
    for (int i = 0; sufijos[i]; i++) {
        rutaf(out, n, "%s/%s%s", dir, nombre, sufijos[i]);
        if (es_archivo(out)) return 1;
    }
    return 0;
}

static int buscar_archivo(const char *nombre, char *out, size_t n) {
    if (buscar_en_dir(DIR_SERVICIOS, nombre, out, n)) return 1;
    for (int i = 0; DIRS_SISTEMA[i]; i++) {
        if (buscar_en_dir(DIRS_SISTEMA[i], nombre, out, n)) return 1;
    }
    return 0;
}

static int resolver(const char *nombre, char *out, size_t n) {
    if (nombre[0] == '\0' || nombre[0] == '.' || strchr(nombre, '/')) return 0;
    if (buscar_archivo(nombre, out, n)) return 1;
    for (int i = 0; ALIAS[i].nombre; i++) {
        if (strcmp(nombre, ALIAS[i].nombre) == 0 && buscar_archivo(ALIAS[i].alias, out, n)) return 1;
    }
    return 0;
}

static void quitar_sufijo(char *nom) {
    char *dot = strrchr(nom, '.');
    if (dot && (strcmp(dot, ".service") == 0 || strcmp(dot, ".conf") == 0)) *dot = '\0';
}

// sshd.service -> ssh.service debe ser un único servicio: se nombra por el archivo real.
static void nombre_canonico(const char *ruta, char *out, size_t n) {
    char real[PATH_MAX];
    const char *base = realpath(ruta, real) ? real : ruta;
    const char *barra = strrchr(base, '/');
    snprintf(out, n, "%s", barra ? barra + 1 : base);
    quitar_sufijo(out);
}

static char *sin_prefijo(char *v, int *ignorar_error) {
    while (*v && strchr("-@+!:", *v)) {
        if (*v == '-') *ignorar_error = 1;
        v++;
    }
    return v;
}

static void agregar_pre(Unidad *u, const char *cmd, int ignorar_error) {
    size_t len = strlen(u->exec_pre);
    snprintf(u->exec_pre + len, sizeof(u->exec_pre) - len,
             ignorar_error ? "%s{ %s; } || true" : "%s%s",
             len ? " && " : "", cmd);
}

// Sin systemd no corre sshdgenkeys.service: las claves de host que falten se crean antes que nada (también antes
// del "sshd -t" de Debian, que falla sin ellas).
static void anteponer_claves_ssh(Unidad *u) {
    char resto[CMD_MAX];
    snprintf(resto, sizeof(resto), "%s", u->exec_pre);
    u->exec_pre[0] = '\0';
    agregar_pre(u, "ssh-keygen -A", 1);
    if (resto[0]) {
        size_t len = strlen(u->exec_pre);
        snprintf(u->exec_pre + len, sizeof(u->exec_pre) - len, " && %s", resto);
    }
}

// Demonios que por defecto se bifurcan: se fuerzan a primer plano bajo el supervisor.
static void adaptar_primer_plano(Unidad *u) {
    const char *extra = NULL;
    if (strcmp(u->nombre, "nginx") == 0 && !strstr(u->exec_start, "daemon off")) {
        extra = " -g 'daemon off;'";
    } else if ((strcmp(u->nombre, "httpd") == 0 || strcmp(u->nombre, "apache2") == 0)
               && !strstr(u->exec_start, "-DFOREGROUND")) {
        extra = " -DFOREGROUND";
    } else if (strcmp(u->nombre, "sshd") == 0 || strcmp(u->nombre, "ssh") == 0) {
        anteponer_claves_ssh(u);
        if (!strstr(u->exec_start, " -D")) extra = " -D";
    }
    if (extra) strncat(u->exec_start, extra, sizeof(u->exec_start) - strlen(u->exec_start) - 1);
}

static void copiar(char *dst, size_t n, const char *src) {
    snprintf(dst, n, "%s", src);
}

int unidad_cargar(const char *nombre, Unidad *u) {
    memset(u, 0, sizeof(*u));
    char ruta[512];
    if (!resolver(nombre, ruta, sizeof(ruta))) return -1;

    copiar(u->origen, sizeof(u->origen), ruta);
    nombre_canonico(ruta, u->nombre, sizeof(u->nombre));
    copiar(u->descripcion, sizeof(u->descripcion), u->nombre);
    u->restart_always = 1;

    char prefijo[256];
    rutaf(prefijo, sizeof(prefijo), "%s/", DIR_SERVICIOS);
    u->en_servicesd = strncmp(ruta, prefijo, strlen(prefijo)) == 0;

    FILE *f = fopen(ruta, "r");
    if (!f) return -1;

    char line[CMD_MAX + 64];
    while (fgets(line, sizeof(line), f)) {
        trim(line);
        if (line[0] == '#' || line[0] == ';' || line[0] == '\0' || line[0] == '[') continue;

        char *eq = strchr(line, '=');
        if (!eq) continue;
        *eq = '\0';
        char *k = line; trim(k);
        char *v = eq + 1; trim(v);
        int ignorar = 0;

        if (strcasecmp(k, "ExecStart") == 0 || strcasecmp(k, "command") == 0) {
            // "ExecStart=" vacío reinicia la lista, como en systemd
            copiar(u->exec_start, sizeof(u->exec_start), sin_prefijo(v, &ignorar));
        } else if (strcasecmp(k, "ExecStartPre") == 0) {
            if (v[0] == '\0') u->exec_pre[0] = '\0';
            else agregar_pre(u, sin_prefijo(v, &ignorar), ignorar);
        } else if (strcasecmp(k, "ExecStop") == 0 || strcasecmp(k, "stop") == 0) {
            copiar(u->exec_stop, sizeof(u->exec_stop), sin_prefijo(v, &ignorar));
        } else if (strcasecmp(k, "EnvironmentFile") == 0) {
            copiar(u->env_file, sizeof(u->env_file), sin_prefijo(v, &ignorar));
        } else if (strcasecmp(k, "RuntimeDirectory") == 0) {
            char *sp = strchr(v, ' ');
            if (sp) *sp = '\0';
            copiar(u->runtime_dir, sizeof(u->runtime_dir), v);
        } else if (strcasecmp(k, "WorkingDirectory") == 0 || strcasecmp(k, "dir") == 0) {
            copiar(u->working_dir, sizeof(u->working_dir), v);
        } else if (strcasecmp(k, "Description") == 0) {
            copiar(u->descripcion, sizeof(u->descripcion), v);
        } else if (strcasecmp(k, "Restart") == 0) {
            u->restart_always = !(strcasecmp(v, "no") == 0 || strcasecmp(v, "never") == 0);
        }
    }
    fclose(f);
    if (u->exec_start[0] == '\0') return -1;

    adaptar_primer_plano(u);
    return 0;
}

void unidad_listar(int incluir_sistema, void (*cb)(const char *nombre, void *ctx), void *ctx) {
    const char *dirs[8];
    int nd = 0;
    dirs[nd++] = DIR_SERVICIOS;
    if (incluir_sistema) {
        for (int i = 0; DIRS_SISTEMA[i]; i++) dirs[nd++] = DIRS_SISTEMA[i];
    }

    for (int j = 0; j < nd; j++) {
        char ruta[512];
        rutaf(ruta, sizeof(ruta), "%s", dirs[j]);
        DIR *d = opendir(ruta);
        if (!d) continue;
        struct dirent *de;
        while ((de = readdir(d))) {
            if (de->d_name[0] == '.') continue;
            char nom[64];
            copiar(nom, sizeof(nom), de->d_name);
            quitar_sufijo(nom);
            cb(nom, ctx);
        }
        closedir(d);
    }
}

void unidad_dirs_texto(char *out, size_t maxlen) {
    size_t off = snprintf(out, maxlen, "%s", DIR_SERVICIOS);
    for (int i = 0; DIRS_SISTEMA[i] && off < maxlen; i++) {
        off += snprintf(out + off, maxlen - off, ", %s", DIRS_SISTEMA[i]);
    }
}
