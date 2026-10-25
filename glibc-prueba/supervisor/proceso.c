#define _GNU_SOURCE
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
#include "common.h"
#include "proceso.h"

#define LOGS_DIR "/var/log/supervisor"

static Servicio *g_servicios = NULL;
static int g_cantidad = 0;
static int g_capacidad = 0;

int servicios_cantidad(void) { return g_cantidad; }
Servicio *servicio_en(int i) { return &g_servicios[i]; }

static Servicio *registrado(const char *nombre) {
    for (int i = 0; i < g_cantidad; i++) {
        if (strcmp(g_servicios[i].u.nombre, nombre) == 0) return &g_servicios[i];
    }
    return NULL;
}

Servicio *servicio_obtener(const char *nombre) {
    Unidad u;
    if (unidad_cargar(nombre, &u) < 0) {
        // Unidad borrada de disco pero aún en marcha: se puede seguir gestionando.
        return registrado(nombre);
    }

    Servicio *s = registrado(u.nombre);
    if (s) {
        // Parado: releer la definición por si cambió en disco.
        if (s->pid <= 0) s->u = u;
        return s;
    }

    if (g_cantidad >= g_capacidad) {
        int nueva = g_capacidad ? g_capacidad * 2 : 16;
        Servicio *arr = realloc(g_servicios, nueva * sizeof(Servicio));
        if (!arr) return NULL;
        g_servicios = arr;
        g_capacidad = nueva;
    }
    s = &g_servicios[g_cantidad++];
    memset(s, 0, sizeof(*s));
    s->u = u;
    return s;
}

int servicio_corriendo(const Servicio *s) {
    return s->pid > 0 && kill(s->pid, 0) == 0;
}

long servicio_uptime(const Servicio *s) {
    return servicio_corriendo(s) ? (long)(time(NULL) - s->start_time) : 0;
}

// Script que ejecuta el hijo: entorno, directorio de runtime, ExecStartPre y ExecStart.
static void armar_comando(const Unidad *u, char *out, size_t n) {
    size_t off = 0;
    if (u->env_file[0]) {
        off += snprintf(out + off, n - off,
                        "set -a; [ -r '%s' ] && . '%s'; set +a; ", u->env_file, u->env_file);
    }
    if (u->runtime_dir[0] && off < n) {
        off += snprintf(out + off, n - off, "mkdir -p '/run/%s' 2>/dev/null; ", u->runtime_dir);
    }
    if (u->exec_pre[0] && off < n) {
        off += snprintf(out + off, n - off, "%s && ", u->exec_pre);
    }
    if (off < n) snprintf(out + off, n - off, "exec %s", u->exec_start);
}

int servicio_iniciar(Servicio *s) {
    if (servicio_corriendo(s)) return 0;

    char dir[512], logpath[600];
    rutaf(dir, sizeof(dir), "%s", LOGS_DIR);
    mkdir(dir, 0755);
    rutaf(logpath, sizeof(logpath), "%s/%s.log", LOGS_DIR, s->u.nombre);

    int log_fd = open(logpath, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (log_fd < 0) log_fd = open("/dev/null", O_WRONLY);

    time_t now = time(NULL);
    char timestr[64];
    strftime(timestr, sizeof(timestr), "%Y-%m-%d %H:%M:%S", localtime(&now));
    dprintf(log_fd, "\n--- INICIO [%s] ---\n", timestr);

    char comando[4096];
    armar_comando(&s->u, comando, sizeof(comando));

    pid_t pid = fork();
    if (pid == 0) {
        setpgid(0, 0);
        dup2(log_fd, STDOUT_FILENO);
        dup2(log_fd, STDERR_FILENO);
        close(log_fd);

        int devnull = open("/dev/null", O_RDONLY);
        if (devnull >= 0) {
            dup2(devnull, STDIN_FILENO);
            close(devnull);
        }

        if (s->u.working_dir[0] && chdir(s->u.working_dir) != 0) chdir("/");

        execl("/bin/sh", "sh", "-c", comando, (char *)NULL);
        exit(127);
    }

    if (log_fd >= 0) close(log_fd);

    if (pid > 0) {
        s->pid = pid;
        s->start_time = time(NULL);
        s->wanted_state = 1;
        return 0;
    }
    return -1;
}

void servicio_detener(Servicio *s) {
    s->wanted_state = 0;
    if (s->pid <= 0) return;

    if (s->u.exec_stop[0]) system(s->u.exec_stop);

    kill(-s->pid, SIGTERM);
    kill(s->pid, SIGTERM);

    for (int i = 0; i < 20; i++) {
        if (kill(s->pid, 0) != 0) break;
        usleep(100000);
    }

    if (kill(s->pid, 0) == 0) {
        kill(-s->pid, SIGKILL);
        kill(s->pid, SIGKILL);
    }
    s->pid = 0;
}

void servicios_revisar_hijos(void) {
    int status;
    pid_t p;
    while ((p = waitpid(-1, &status, WNOHANG)) > 0) {
        for (int i = 0; i < g_cantidad; i++) {
            Servicio *s = &g_servicios[i];
            if (s->pid != p) continue;
            s->pid = 0;
            if (s->wanted_state == 1 && s->u.restart_always) {
                s->restart_count++;
                usleep(500000);
                servicio_iniciar(s);
            }
            break;
        }
    }
}
