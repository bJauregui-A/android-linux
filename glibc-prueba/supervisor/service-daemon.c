#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <errno.h>
#include <time.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <dirent.h>

#define MAX_SERVICES 128
#define LINE_MAX_LEN 1024
#define SERVICES_DIR "/etc/services.d"
#define SYSTEM_UNITS_DIR "/usr/lib/systemd/system"
#define LOGS_DIR "/var/log/supervisor"
#define STATE_DIR "/var/lib/supervisor"
#define ENABLED_FILE "/var/lib/supervisor/enabled.txt"

typedef struct {
    char name[64];
    char exec_start[512];
    char exec_stop[512];
    char working_dir[256];
    char description[128];
    int restart_always;
    pid_t pid;
    time_t start_time;
    int restart_count;
    int wanted_state; // 1 = running, 0 = stopped
} Service;

static Service g_services[MAX_SERVICES];
static int g_num_services = 0;
static volatile sig_atomic_t g_running = 1;

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

static void trim(char *s) {
    int i = strlen(s) - 1;
    while (i >= 0 && (s[i] == ' ' || s[i] == '\t' || s[i] == '\r' || s[i] == '\n')) {
        s[i--] = '\0';
    }
    char *p = s;
    while (*p == ' ' || *p == '\t') p++;
    if (p != s) memmove(s, p, strlen(p) + 1);
}

static int es_habilitado(const char *name) {
    FILE *f = fopen(ENABLED_FILE, "r");
    if (!f) return 0;
    char line[128];
    while (fgets(line, sizeof(line), f)) {
        trim(line);
        if (strcmp(line, name) == 0) {
            fclose(f);
            return 1;
        }
    }
    fclose(f);
    return 0;
}

static void set_habilitado(const char *name, int enable) {
    char target[512], linkpath[512];
    snprintf(linkpath, sizeof(linkpath), "%s/%s.service", SERVICES_DIR, name);
    if (enable) {
        snprintf(target, sizeof(target), "%s/%s.service", SYSTEM_UNITS_DIR, name);
        if (access(target, R_OK) == 0 && access(linkpath, F_OK) != 0) {
            symlink(target, linkpath);
        }
    } else {
        if (access(linkpath, F_OK) == 0) {
            unlink(linkpath);
        }
    }

    mkdir(STATE_DIR, 0755);
    char tmp[256];
    snprintf(tmp, sizeof(tmp), "%s.tmp", ENABLED_FILE);

    FILE *f_in = fopen(ENABLED_FILE, "r");
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
            if (strcmp(line, name) == 0) {
                if (enable) {
                    fprintf(f_out, "%s\n", name);
                    ya_estaba = 1;
                }
            } else if (line[0] != '\0') {
                fprintf(f_out, "%s\n", line);
            }
        }
        fclose(f_in);
    }
    if (enable && !ya_estaba) {
        fprintf(f_out, "%s\n", name);
    }
    fclose(f_out);
    rename(tmp, ENABLED_FILE);
}

static int parsear_unidad(const char *name, Service *srv) {
    memset(srv, 0, sizeof(Service));
    strncpy(srv->name, name, sizeof(srv->name) - 1);
    srv->restart_always = 1; // default on-failure/always
    strncpy(srv->description, name, sizeof(srv->description) - 1);

    char filepath[512];
    int encontrado = 0;
    const char *dirs[] = { SERVICES_DIR, SYSTEM_UNITS_DIR, NULL };
    for (int i = 0; dirs[i] != NULL && !encontrado; i++) {
        snprintf(filepath, sizeof(filepath), "%s/%s", dirs[i], name);
        if (access(filepath, R_OK) == 0) { encontrado = 1; break; }
        snprintf(filepath, sizeof(filepath), "%s/%s.service", dirs[i], name);
        if (access(filepath, R_OK) == 0) { encontrado = 1; break; }
        snprintf(filepath, sizeof(filepath), "%s/%s.conf", dirs[i], name);
        if (access(filepath, R_OK) == 0) { encontrado = 1; break; }
    }
    if (!encontrado) return -1;

    FILE *f = fopen(filepath, "r");
    if (!f) return -1;

    char line[LINE_MAX_LEN];
    while (fgets(line, sizeof(line), f)) {
        trim(line);
        if (line[0] == '#' || line[0] == ';' || line[0] == '\0' || line[0] == '[')
            continue;

        char *eq = strchr(line, '=');
        if (!eq) continue;
        *eq = '\0';
        char *k = line; trim(k);
        char *v = eq + 1; trim(v);

        if (strcasecmp(k, "ExecStart") == 0 || strcasecmp(k, "command") == 0) {
            if (v[0] == '-') v++; // ignore errors flag
            strncpy(srv->exec_start, v, sizeof(srv->exec_start) - 1);
        } else if (strcasecmp(k, "ExecStop") == 0 || strcasecmp(k, "stop") == 0) {
            strncpy(srv->exec_stop, v, sizeof(srv->exec_stop) - 1);
        } else if (strcasecmp(k, "WorkingDirectory") == 0 || strcasecmp(k, "dir") == 0) {
            strncpy(srv->working_dir, v, sizeof(srv->working_dir) - 1);
        } else if (strcasecmp(k, "Description") == 0) {
            strncpy(srv->description, v, sizeof(srv->description) - 1);
        } else if (strcasecmp(k, "Restart") == 0 || strcasecmp(k, "restart") == 0) {
            if (strcasecmp(v, "no") == 0 || strcasecmp(v, "never") == 0) {
                srv->restart_always = 0;
            } else {
                srv->restart_always = 1;
            }
        }
    }
    fclose(f);
    return (srv->exec_start[0] != '\0') ? 0 : -1;
}

static Service *buscar_o_crear(const char *name) {
    for (int i = 0; i < g_num_services; i++) {
        if (strcmp(g_services[i].name, name) == 0) {
            return &g_services[i];
        }
    }
    if (g_num_services >= MAX_SERVICES) return NULL;

    Service *s = &g_services[g_num_services];
    if (parsear_unidad(name, s) < 0) {
        return NULL;
    }
    g_num_services++;
    return s;
}

static int iniciar_servicio(Service *s) {
    if (s->pid > 0 && kill(s->pid, 0) == 0) {
        return 0; // ya corriendo
    }

    mkdir(LOGS_DIR, 0755);
    char logpath[512];
    snprintf(logpath, sizeof(logpath), "%s/%s.log", LOGS_DIR, s->name);

    int log_fd = open(logpath, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (log_fd < 0) log_fd = open("/dev/null", O_WRONLY);

    time_t now = time(NULL);
    char timestr[64];
    strftime(timestr, sizeof(timestr), "%Y-%m-%d %H:%M:%S", localtime(&now));
    dprintf(log_fd, "\n--- INICIO [%s] ---\n", timestr);

    pid_t pid = fork();
    if (pid == 0) {
        // Hijo
        setpgid(0, 0);
        dup2(log_fd, STDOUT_FILENO);
        dup2(log_fd, STDERR_FILENO);
        close(log_fd);

        int devnull = open("/dev/null", O_RDONLY);
        if (devnull >= 0) {
            dup2(devnull, STDIN_FILENO);
            close(devnull);
        }

        if (s->working_dir[0] && chdir(s->working_dir) != 0) {
            chdir("/");
        }

        execl("/bin/sh", "sh", "-c", s->exec_start, (char *)NULL);
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

static void detener_servicio(Service *s) {
    s->wanted_state = 0;
    if (s->pid <= 0) return;

    if (s->exec_stop[0]) {
        system(s->exec_stop);
    }

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

static void check_hijos(void) {
    int status;
    pid_t p;
    while ((p = waitpid(-1, &status, WNOHANG)) > 0) {
        for (int i = 0; i < g_num_services; i++) {
            Service *s = &g_services[i];
            if (s->pid == p) {
                s->pid = 0;
                if (s->wanted_state == 1 && s->restart_always) {
                    s->restart_count++;
                    usleep(500000);
                    iniciar_servicio(s);
                }
                break;
            }
        }
    }
}

static void auto_iniciar_habilitados(void) {
    FILE *f = fopen(ENABLED_FILE, "r");
    if (!f) return;
    char line[128];
    while (fgets(line, sizeof(line), f)) {
        trim(line);
        if (line[0] != '\0') {
            Service *s = buscar_o_crear(line);
            if (s) {
                iniciar_servicio(s);
            }
        }
    }
    fclose(f);
}

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

    char resp[4096];
    memset(resp, 0, sizeof(resp));

    if (strcasecmp(cmd, "PING") == 0) {
        snprintf(resp, sizeof(resp), "PONG\n");
    } else if (strcasecmp(cmd, "START") == 0) {
        Service *s = buscar_o_crear(arg);
        if (!s) {
            snprintf(resp, sizeof(resp), "ERR No se encontró el servicio '%s'\n", arg);
        } else if (iniciar_servicio(s) == 0) {
            snprintf(resp, sizeof(resp), "OK Servicio %s iniciado (PID %d)\n", s->name, s->pid);
        } else {
            snprintf(resp, sizeof(resp), "ERR Fallo al iniciar %s\n", arg);
        }
    } else if (strcasecmp(cmd, "STOP") == 0) {
        Service *s = buscar_o_crear(arg);
        if (!s) {
            snprintf(resp, sizeof(resp), "ERR Servicio '%s' no encontrado\n", arg);
        } else {
            detener_servicio(s);
            snprintf(resp, sizeof(resp), "OK Servicio %s detenido\n", s->name);
        }
    } else if (strcasecmp(cmd, "RESTART") == 0) {
        Service *s = buscar_o_crear(arg);
        if (!s) {
            snprintf(resp, sizeof(resp), "ERR Servicio '%s' no encontrado\n", arg);
        } else {
            detener_servicio(s);
            usleep(200000);
            iniciar_servicio(s);
            snprintf(resp, sizeof(resp), "OK Servicio %s reiniciado (PID %d)\n", s->name, s->pid);
        }
    } else if (strcasecmp(cmd, "ENABLE") == 0) {
        Service *s = buscar_o_crear(arg);
        if (!s) {
            snprintf(resp, sizeof(resp), "ERR Servicio '%s' no encontrado\n", arg);
        } else {
            set_habilitado(s->name, 1);
            iniciar_servicio(s);
            snprintf(resp, sizeof(resp), "OK Servicio %s habilitado para auto-arranque\n", s->name);
        }
    } else if (strcasecmp(cmd, "DISABLE") == 0) {
        Service *s = buscar_o_crear(arg);
        if (!s) {
            snprintf(resp, sizeof(resp), "ERR Servicio '%s' no encontrado\n", arg);
        } else {
            set_habilitado(s->name, 0);
            snprintf(resp, sizeof(resp), "OK Servicio %s deshabilitado\n", s->name);
        }
    } else if (strcasecmp(cmd, "STATUS") == 0) {
        Service *s = buscar_o_crear(arg);
        if (!s) {
            snprintf(resp, sizeof(resp), "ERR Servicio '%s' no encontrado\n", arg);
        } else {
            int running = (s->pid > 0 && kill(s->pid, 0) == 0);
            int enab = es_habilitado(s->name);
            long uptime = running ? (long)(time(NULL) - s->start_time) : 0;
            snprintf(resp, sizeof(resp), "OK %s|%s|%d|%ld|%d|%d|%s\n",
                     s->name, running ? "running" : "stopped",
                     running ? s->pid : 0, uptime, s->restart_count, enab, s->description);
        }
    } else if (strcasecmp(cmd, "LIST") == 0) {
        const char *dirs[] = { SERVICES_DIR, SYSTEM_UNITS_DIR, NULL };
        for (int j = 0; dirs[j] != NULL; j++) {
            DIR *d = opendir(dirs[j]);
            if (d) {
                struct dirent *de;
                while ((de = readdir(d))) {
                    if (de->d_name[0] == '.') continue;
                    char nom[64];
                    strncpy(nom, de->d_name, sizeof(nom) - 1);
                    nom[sizeof(nom) - 1] = '\0';
                    char *dot = strrchr(nom, '.');
                    if (dot && (strcmp(dot, ".service") == 0 || strcmp(dot, ".conf") == 0)) *dot = '\0';
                    buscar_o_crear(nom);
                }
                closedir(d);
            }
        }

        size_t off = 0;
        for (int i = 0; i < g_num_services && off < sizeof(resp) - 256; i++) {
            Service *s = &g_services[i];
            int running = (s->pid > 0 && kill(s->pid, 0) == 0);
            int enab = es_habilitado(s->name);
            long uptime = running ? (long)(time(NULL) - s->start_time) : 0;
            off += snprintf(resp + off, sizeof(resp) - off, "SRV %s|%s|%d|%ld|%d|%s\n",
                            s->name, running ? "running" : "stopped",
                            running ? s->pid : 0, uptime, enab, s->description);
        }
        snprintf(resp + off, sizeof(resp) - off, "END\n");
    } else {
        snprintf(resp, sizeof(resp), "ERR Comando desconocido\n");
    }

    write(client_fd, resp, strlen(resp));
    close(client_fd);
}

int main(int argc, char **argv) {
    (void)argc; (void)argv;
    signal(SIGPIPE, SIG_IGN);

    char sock_path[256];
    obtener_socket_path(sock_path, sizeof(sock_path));

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

    // Cargar e iniciar servicios habilitados
    auto_iniciar_habilitados();

    int flags = fcntl(sfd, F_GETFL, 0);
    fcntl(sfd, F_SETFL, flags | O_NONBLOCK);

    while (g_running) {
        check_hijos();

        int cfd = accept(sfd, NULL, NULL);
        if (cfd >= 0) {
            manejar_cliente(cfd);
        } else {
            usleep(100000); // 100ms
        }
    }

    close(sfd);
    unlink(sock_path);
    return 0;
}
