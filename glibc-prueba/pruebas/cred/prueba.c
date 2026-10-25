/* Pruebas de las credenciales virtuales (B27, fase 1).  Un caso por argumento:
     prueba <caso>      imprime "OK <caso>" o "FALLA <caso>: ..." (salida 0 / 1)
     prueba ids         imprime "r e s f gr ge gs gf g1,g2..." (para comparar tras exec)
   test.sh pone GLIBC_FAKEROOT=1 en los casos que parten de root; el resto del
   estado se arma con set*id (por entorno no se puede falsificar GLIBC_CRED:
   cada execve de la glibc lo reescribe).  */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/fsuid.h>
#include <sys/wait.h>
#include <sys/xattr.h>
#include <unistd.h>

static int fallas;
static const char *caso;

#define CHECK(cond, ...)						\
  do {									\
    if (!(cond)) {							\
      printf ("FALLA %s: línea %d: %s", caso, __LINE__, #cond);	\
      printf (" " __VA_ARGS__);						\
      printf ("\n");							\
      fallas++;								\
    }									\
  } while (0)

#define M1 ((uid_t) -1)

static void
ids (char *out, size_t n)
{
  uid_t r, e, s;
  gid_t gr, ge, gs;
  getresuid (&r, &e, &s);
  getresgid (&gr, &ge, &gs);
  int off = snprintf (out, n, "%u %u %u %u %u %u %u %u ", r, e, s,
		      (unsigned) setfsuid (M1), gr, ge, gs,
		      (unsigned) setfsgid (M1));
  gid_t g[64];
  int ng = getgroups (64, g);
  for (int i = 0; i < ng && off < (int) n - 12; i++)
    off += snprintf (out + off, n - off, "%s%u", i ? "," : "", g[i]);
}

/* uid real del kernel, de /proc/self/status.  */
static unsigned
uid_kernel (void)
{
  FILE *f = fopen ("/proc/self/status", "r");
  char l[256];
  unsigned u = 0;
  while (f && fgets (l, sizeof l, f))
    if (sscanf (l, "Uid: %u", &u) == 1)
      break;
  if (f)
    fclose (f);
  return u;
}

static int
ids_igual (const char *esperado)
{
  char b[512];
  ids (b, sizeof b);
  if (strcmp (b, esperado) != 0)
    {
      printf ("FALLA %s: ids '%s' esperado '%s'\n", caso, b, esperado);
      fallas++;
      return 0;
    }
  return 1;
}

static void
c_real (void)
{
  unsigned k = uid_kernel ();
  CHECK (getuid () == k && geteuid () == k, "uid %u kernel %u", getuid (), k);
  CHECK (setuid (getuid ()) == 0);
  CHECK (setresuid (M1, M1, M1) == 0);
  CHECK (setuid (0) == -1 && errno == EPERM, "errno %d", errno);
  CHECK (setgroups (0, NULL) == -1 && errno == EPERM);
}

static void
c_fake (void)
{
  ids_igual ("0 0 0 0 0 0 0 0 ");
  gid_t g[2] = { 5, 6 };
  CHECK (setgroups (2, g) == 0);
  ids_igual ("0 0 0 0 0 0 0 0 5,6");
  CHECK (setresgid (100, 100, 100) == 0);
  CHECK (setresuid (200, 300, 400) == 0);
  ids_igual ("200 300 400 300 100 100 100 100 5,6");
  CHECK (seteuid (0) == -1 && errno == EPERM);   /* 0 no es r/e/s */
  CHECK (seteuid (400) == 0);
  CHECK (geteuid () == 400 && getuid () == 200);
  CHECK (seteuid (200) == 0);
  CHECK (setgroups (0, NULL) == -1 && errno == EPERM);
  CHECK (setgid (7) == -1 && errno == EPERM);     /* ya no es root */
  CHECK (setfsuid (999) == 200, "setfsuid");      /* devuelve el anterior */
  CHECK (setfsuid (M1) == 200, "no cambió");      /* 999 no estaba permitido */
}

static void
c_cred (void)
{
  gid_t g0[2] = { 10, 20 };
  CHECK (setgroups (2, g0) == 0);
  CHECK (setresgid (1000, 1000, 1000) == 0);
  CHECK (setresuid (1000, 1000, 1000) == 0);
  ids_igual ("1000 1000 1000 1000 1000 1000 1000 1000 10,20");
  CHECK (setuid (0) == -1 && errno == EPERM);
  CHECK (setgid (2000) == -1 && errno == EPERM);
  CHECK (setreuid (M1, 1000) == 0);
  CHECK (setregid (1000, M1) == 0);
  CHECK (setresuid (1000, 1000, 1000) == 0);
  CHECK (setresuid (1, M1, M1) == -1 && errno == EPERM);
  gid_t g[1];
  CHECK (getgroups (1, g) == -1 && errno == EINVAL, "lista chica");
  CHECK (getgroups (0, NULL) == 2);
}

/* root con euid temporalmente bajo: puede volver (suid = 0).  */
static void
c_cola (void)
{
  CHECK (setresgid (0, 1000, 0) == 0);
  CHECK (setresuid (0, 1000, 0) == 0);
  ids_igual ("0 1000 0 1000 0 1000 0 1000 ");
  CHECK (seteuid (0) == 0);
  CHECK (geteuid () == 0);
  CHECK (setuid (1234) == 0);                      /* root: r=e=s=1234 */
  ids_igual ("1234 1234 1234 1234 0 1000 0 1000 ");
  CHECK (seteuid (0) == -1 && errno == EPERM);     /* ya no puede volver */
}

static void
c_ids (void)
{
  char b[512];
  ids (b, sizeof b);
  puts (b);
}

/* Cambia los ids y relanza ./prueba ids con el entorno vacío.  */
static void
c_exec (const char *yo, int via_env)
{
  gid_t g[2] = { 5, 6 };
  CHECK (setgroups (2, g) == 0);
  CHECK (setresgid (100, 101, 102) == 0);
  CHECK (setresuid (200, 300, 400) == 0);
  fflush (stdout);
  int p[2];
  CHECK (pipe (p) == 0);
  pid_t pid = fork ();
  if (pid == 0)
    {
      dup2 (p[1], 1);
      char *vacio[] = { NULL };
      if (via_env)
	{
	  char *a[] = { "/usr/bin/env", "-i", (char *) yo, "ids", NULL };
	  execve ("/usr/bin/env", a, vacio);
	}
      else
	{
	  char *a[] = { (char *) yo, "ids", NULL };
	  execve (yo, a, vacio);
	}
      _exit (127);
    }
  close (p[1]);
  char b[512] = "";
  ssize_t n = read (p[0], b, sizeof b - 1);
  if (n > 0)
    b[n] = 0;
  while (n > 0 && (b[n - 1] == '\n'))
    b[--n] = 0;
  int st;
  waitpid (pid, &st, 0);
  /* como en Linux, el execve copia el efectivo al guardado (y al fs) */
  const char *esperado = "200 300 300 300 100 101 101 101 5,6";
  CHECK (strcmp (b, esperado) == 0, "hijo '%s' esperado '%s'", b, esperado);
  /* un fork sin exec también hereda */
  if (fork () == 0)
    {
      char c[512];
      ids (c, sizeof c);
      _exit (strcmp (c, "200 300 400 300 100 101 102 101 5,6") == 0 ? 0 : 1);
    }
  wait (&st);
  CHECK (WIFEXITED (st) && WEXITSTATUS (st) == 0, "fork");
}

static void
c_stat (void)
{
  unsigned k = uid_kernel ();
  struct stat st;
  struct statx sx;
  const char *root[] = { "/", "/etc/passwd", "/usr/bin", "/var", "/etc" };
  const char *user[] = { "/tmp", "/home" };
  for (int i = 0; i < 5; i++)
    {
      CHECK (stat (root[i], &st) == 0, "%s", root[i]);
      CHECK (st.st_uid == 0 && st.st_gid == 0, "%s uid %u", root[i], st.st_uid);
      CHECK (statx (AT_FDCWD, root[i], 0, STATX_BASIC_STATS, &sx) == 0);
      CHECK (sx.stx_uid == 0, "statx %s", root[i]);
    }
  for (int i = 0; i < 2; i++)
    {
      CHECK (stat (user[i], &st) == 0, "%s", user[i]);
      CHECK (st.st_uid == k, "%s uid %u kernel %u", user[i], st.st_uid, k);
    }
  int fd = open ("/etc/passwd", O_RDONLY);
  CHECK (fd >= 0 && fstat (fd, &st) == 0 && st.st_uid == 0, "fstat");
  close (fd);
  int d = open ("/etc", O_RDONLY | O_DIRECTORY);
  CHECK (d >= 0 && fstatat (d, "passwd", &st, 0) == 0 && st.st_uid == 0,
	 "fstatat relativo");
  close (d);
  CHECK (chdir ("/etc") == 0 && stat ("passwd", &st) == 0 && st.st_uid == 0,
	 "relativo al cwd");
  chdir ("/tmp");

  /* xattr de dueño: manda sobre la regla */
  const char *f = "/tmp/cred-prueba-x", *l = "/tmp/cred-prueba-l";
  unlink (f);
  unlink (l);
  fd = open (f, O_CREAT | O_WRONLY, 0644);
  CHECK (fd >= 0);
  CHECK (stat (f, &st) == 0 && st.st_uid == k, "sin xattr: regla");
  CHECK (fsetxattr (fd, "user.linux.owner", "1234:5678", 9, 0) == 0,
	 "setxattr errno %d", errno);
  CHECK (stat (f, &st) == 0 && st.st_uid == 1234 && st.st_gid == 5678,
	 "con xattr: %u:%u", st.st_uid, st.st_gid);
  CHECK (fstat (fd, &st) == 0 && st.st_uid == 1234, "fstat con xattr");
  CHECK (statx (AT_FDCWD, f, 0, STATX_BASIC_STATS, &sx) == 0
	 && sx.stx_uid == 1234 && sx.stx_gid == 5678, "statx con xattr");
  /* el enlace simbólico no tiene xattr: regla */
  CHECK (symlink (f, l) == 0);
  CHECK (lstat (l, &st) == 0 && st.st_uid == k, "lstat enlace %u", st.st_uid);
  CHECK (stat (l, &st) == 0 && st.st_uid == 1234, "stat sigue el enlace");
  /* el xattr gana también en la zona de root */
  close (fd);
  unlink (f);
  unlink (l);
}

int
main (int argc, char **argv)
{
  caso = argc > 1 ? argv[1] : "?";
  if (!strcmp (caso, "ids")) c_ids ();
  else if (!strcmp (caso, "real")) c_real ();
  else if (!strcmp (caso, "fake")) c_fake ();
  else if (!strcmp (caso, "cred")) c_cred ();
  else if (!strcmp (caso, "cola")) c_cola ();
  else if (!strcmp (caso, "exec")) c_exec (argv[0], 0);
  else if (!strcmp (caso, "execenv")) c_exec (argv[0], 1);
  else if (!strcmp (caso, "stat")) c_stat ();
  else { printf ("caso desconocido %s\n", caso); return 2; }
  if (strcmp (caso, "ids") == 0)
    return 0;
  if (!fallas)
    printf ("OK %s\n", caso);
  return fallas ? 1 : 0;
}
