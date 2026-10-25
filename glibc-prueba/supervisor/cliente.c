#define _GNU_SOURCE
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include "cliente.h"
#include "common.h"

int conectar_demonio(void) {
    char sock_path[256];
    ruta_socket(sock_path, sizeof(sock_path));

    for (int intento = 0; intento < 2; intento++) {
        int fd = socket(AF_UNIX, SOCK_STREAM, 0);
        if (fd < 0) return -1;

        struct sockaddr_un addr;
        memset(&addr, 0, sizeof(addr));
        addr.sun_family = AF_UNIX;
        strncpy(addr.sun_path, sock_path, sizeof(addr.sun_path) - 1);

        if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) == 0) return fd;
        close(fd);

        if (intento == 0) {
            if (fork() == 0) {
                close(0); close(1); close(2);
                const char *demonio = getenv("SERVICE_DAEMON");
                execl(demonio ? demonio : "/usr/local/bin/service-daemon", "service-daemon", (char *)NULL);
                exit(1);
            }
            usleep(250000);
        }
    }
    return -1;
}

long pedir_al_demonio(const char *req, char *resp, size_t maxlen) {
    int sfd = conectar_demonio();
    if (sfd < 0) return -1;

    if (write(sfd, req, strlen(req)) < 0) {
        close(sfd);
        return 0;
    }

    size_t total = 0;
    while (total < maxlen - 1) {
        ssize_t n = read(sfd, resp + total, maxlen - 1 - total);
        if (n <= 0) break;
        total += n;
    }
    close(sfd);
    resp[total] = '\0';
    return total;
}
