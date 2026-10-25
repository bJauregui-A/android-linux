/* Pruebas C1-C12 del resolvedor de raíz cerrada (B26), en el PC.  */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/syscall.h>
#include "android-raiz.h"

static int llamadas;
static char cwd_falso[PATH_MAX];

static long
op_readlinkat (void *ctx, int dirfd, const char *p, char *b, size_t n)
{
  llamadas++;
  ssize_t r = readlinkat (dirfd, p, b, n);
  return r < 0 ? -errno : r;
}

static long
op_getcwd (void *ctx, char *b, size_t n)
{
  llamadas++;
  size_t l = strlen (cwd_falso);
  if (l >= n)
    return -ERANGE;
  memcpy (b, cwd_falso, l);
  return l;
}

static int
op_pasa (void *ctx, const char *v)
{
  return !strncmp (v, "/sdcard", 7) || !strncmp (v, "/proc", 5);
}

static struct raiz_ops ops = { op_readlinkat, op_getcwd, op_pasa, NULL };
static char R[PATH_MAX];	/* prefijo falso */
static int fallas;

static void
ver (const char *id, int dirfd, const char *in, int rc_esp, const char *esp)
{
  char out[PATH_MAX] = "";
  int rc = raiz_resolver (&ops, R, NULL, dirfd, in, out, sizeof out);
  int ok = rc == rc_esp && (rc != 0 || strcmp (out, esp) == 0);
  printf ("%s %s  %-28s -> rc=%d '%s'%s\n", ok ? "OK   " : "FALLA", id, in, rc,
	  out, ok ? "" : "");
  if (!ok)
    {
      fprintf (stderr, "   esperado rc=%d '%s'\n", rc_esp, esp ? esp : "");
      fallas++;
    }
}

int
main (int argc, char **argv)
{
  snprintf (R, sizeof R, "%s", argv[1]);	/* test.sh arma el árbol */
  int raiz_fd = open (R, O_PATH | O_DIRECTORY);

  ver ("C1 ", AT_FDCWD, "/..", 0, "/");
  ver ("C2 ", AT_FDCWD, "/../../..", 0, "/");
  ver ("C3 ", AT_FDCWD, "/../otra-instancia/x", 0, "/otra-instancia/x");
  ver ("C4 ", AT_FDCWD, "/usr/../etc", 0, "/etc");
  ver ("C5 ", AT_FDCWD, "/lib/..", 0, "/usr");
  ver ("C6 ", AT_FDCWD, "/lib/../..", 0, "/");

  snprintf (cwd_falso, sizeof cwd_falso, "%s", R);
  ver ("C7 ", AT_FDCWD, "..", 0, "/");
  snprintf (cwd_falso, sizeof cwd_falso, "%s/home/user", R);
  ver ("C8 ", AT_FDCWD, "../../x", 0, "/x");
  ver ("C9 ", raiz_fd, "..", 0, "/");
  ver ("C21", raiz_fd, "../usr/bin/x", 0, "/usr/bin/x");
  ver ("C10", AT_FDCWD, "/abs/..", 0, "/usr");
  ver ("C11", AT_FDCWD, "/bucle1/../x", -ELOOP, NULL);

  llamadas = 0;
  ver ("C12", AT_FDCWD, "/usr/lib/libc.so", RAIZ_INTACTA, NULL);
  ver ("C12", AT_FDCWD, "relativa/x", RAIZ_INTACTA, NULL);
  if (llamadas != 0)
    {
      fprintf (stderr, "FALLA C12: %d llamadas a OPS en rutas sin '..'\n",
	       llamadas);
      fallas++;
    }

  /* cwd fuera de la instancia: no se toca.  */
  snprintf (cwd_falso, sizeof cwd_falso, "/sdcard/Download");
  ver ("C20", AT_FDCWD, "../x", RAIZ_INTACTA, NULL);

  /* Carpetas de Android: el resolvedor se detiene y deja el resto igual.  */
  ver ("C20", AT_FDCWD, "/sdcard/..", 0, "/sdcard/..");
  ver ("C20", AT_FDCWD, "/proc/self/../x", 0, "/proc/self/../x");

  printf ("%s\n", fallas ? "RESOLVER: FALLA" : "RESOLVER: OK");
  return fallas != 0;
}
