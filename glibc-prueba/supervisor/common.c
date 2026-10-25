#define _GNU_SOURCE
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "common.h"

void trim(char *s) {
    int i = strlen(s) - 1;
    while (i >= 0 && (s[i] == ' ' || s[i] == '\t' || s[i] == '\r' || s[i] == '\n')) {
        s[i--] = '\0';
    }
    char *p = s;
    while (*p == ' ' || *p == '\t') p++;
    if (p != s) memmove(s, p, strlen(p) + 1);
}

void ruta_socket(char *out, size_t maxlen) {
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

void rutaf(char *out, size_t maxlen, const char *fmt, ...) {
    const char *raiz = getenv("SERVICE_ROOT");
    int off = snprintf(out, maxlen, "%s", raiz ? raiz : "");
    if (off < 0 || (size_t)off >= maxlen) return;
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(out + off, maxlen - off, fmt, ap);
    va_end(ap);
}
